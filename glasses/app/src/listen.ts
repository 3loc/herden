/**
 * Continuous microphone capture: pre-roll, energy endpointing, caps.
 *
 * Push-to-talk lost the first syllable of every command. `audioControl(true)`
 * does not take effect instantly, so a wearer who long-pressed and spoke
 * immediately had the opening of the phrase clipped off — "open one" came back
 * from the transcriber as "On", and one clip was pure silence. The fix is not
 * a longer press: it is to keep the microphone open for the whole lit session
 * and to carry a short ring buffer of audio from *before* speech was detected,
 * so an utterance always starts a beat early.
 *
 * Pure and SDK-free: the caller pushes PCM frames in and gets finished
 * utterances out. No timers — byte counts are the clock, which makes every
 * rule here deterministic under test.
 */

import { PCM_FORMAT } from "./audio.ts";

/**
 * Audio retained ahead of detected speech. The clipping this fixes was on the
 * order of a syllable, so half a second is the floor; 600 ms leaves margin for
 * a slow `audioControl` and for the energy threshold reacting a frame late.
 */
export const PREROLL_MS = 600;

/** Silence that ends an utterance. Long enough to think mid-sentence. */
export const SILENCE_END_MS = 1_200;

/** One utterance can never grow past this, however the endpointer behaves. */
export const UTTERANCE_MAX_MS = 15_000;

/**
 * Minimum RMS, as a fraction of int16 full scale, above which a frame can
 * count as speech. The effective threshold rises with the measured noise
 * floor; this only keeps a quiet room from making it vanishingly small.
 */
export const SPEECH_RMS = 0.03;

/** Recent audio used to estimate the changing noise floor. */
export const NOISE_WINDOW_MS = 4_000;

/** A low percentile excludes speech while following sustained background. */
export const NOISE_PERCENTILE = 0.2;

/**
 * The worn G2's ambient floor can sit near 4% while quiet speech is only
 * 8–10%. Requiring 3× that floor classified whole spoken commands as silence
 * (captured clips reached the 15-second cap and STT returned empty). Keep a
 * margin above steady noise without requiring shouted commands.
 */
export const NOISE_MULTIPLIER = 1.8;

/** Avoid treating the first noisy mic frame as speech before a floor exists. */
export const STARTUP_SPEECH_RMS = 0.08;
export const NOISE_CALIBRATION_MS = 400;

/** Trailing silence kept on a finished utterance; the rest is dropped. */
export const TRAILING_SILENCE_KEEP_MS = 400;

export function bytesForMs(ms: number): number {
  const bytesPerSample = PCM_FORMAT.channels * (PCM_FORMAT.bitsPerSample / 8);
  return Math.round((ms / 1000) * PCM_FORMAT.sampleRate) * bytesPerSample;
}

/** Root-mean-square of one frame of signed 16-bit little-endian PCM, 0…1. */
export function frameRms(frame: Uint8Array): number {
  const samples = Math.floor(frame.length / 2);
  if (samples === 0) return 0;
  let sum = 0;
  for (let index = 0; index < samples; index += 1) {
    const raw = (frame[index * 2 + 1]! << 8) | frame[index * 2]!;
    const value = raw >= 0x8000 ? raw - 0x10000 : raw;
    sum += value * value;
  }
  return Math.sqrt(sum / samples) / 0x8000;
}

/**
 * Whether a finished segment holds any speech at all. The transcriber
 * hallucinates words onto silence, so a segment that fails this is dropped
 * rather than sent.
 */
export function containsSpeech(frames: readonly Uint8Array[], threshold: number = SPEECH_RMS): boolean {
  return frames.some((frame) => frameRms(frame) >= threshold);
}

/**
 * Drop whole frames from the front while the buffer still holds at least
 * `limit` bytes without them. Retention is the invariant that matters: the
 * ring may carry more than the pre-roll window, never less.
 */
export function trimPreroll(
  frames: readonly Uint8Array[],
  limit: number = bytesForMs(PREROLL_MS),
): { frames: Uint8Array[]; bytes: number } {
  const kept = [...frames];
  let bytes = kept.reduce((sum, frame) => sum + frame.length, 0);
  while (kept.length > 0 && bytes - kept[0]!.length >= limit) {
    bytes -= kept.shift()!.length;
  }
  return { frames: kept, bytes };
}

export interface ListenOptions {
  prerollBytes: number;
  silenceBytes: number;
  maxUtteranceBytes: number;
  keepTailBytes: number;
  threshold: number;
  noiseWindowBytes: number;
  noisePercentile: number;
  noiseMultiplier: number;
}

export const LISTEN_DEFAULTS: ListenOptions = {
  prerollBytes: bytesForMs(PREROLL_MS),
  silenceBytes: bytesForMs(SILENCE_END_MS),
  maxUtteranceBytes: bytesForMs(UTTERANCE_MAX_MS),
  keepTailBytes: bytesForMs(TRAILING_SILENCE_KEEP_MS),
  threshold: SPEECH_RMS,
  noiseWindowBytes: bytesForMs(NOISE_WINDOW_MS),
  noisePercentile: NOISE_PERCENTILE,
  noiseMultiplier: NOISE_MULTIPLIER,
};

export interface EnergySample {
  readonly rms: number;
  readonly bytes: number;
}

export interface ListenBuffer {
  /** Audio seen before speech started; carried into the next utterance. */
  readonly preroll: readonly Uint8Array[];
  readonly prerollBytes: number;
  /** Frames of the utterance in progress; empty when none is open. */
  readonly utterance: readonly Uint8Array[];
  readonly utteranceBytes: number;
  readonly open: boolean;
  /** Trailing silent bytes inside the open utterance. */
  readonly trailingSilence: number;
  /** Every byte this session has seen; drives the lens byte counter. */
  readonly captured: number;
  /** Rolling frame energies used to follow the ambient noise floor. */
  readonly energy: readonly EnergySample[];
  readonly energyBytes: number;
}

export const EMPTY_LISTEN: ListenBuffer = {
  preroll: [], prerollBytes: 0, utterance: [], utteranceBytes: 0, open: false, trailingSilence: 0, captured: 0,
  energy: [], energyBytes: 0,
};

/** Why an utterance was handed back. */
export type EndpointReason = "silence" | "cap";

export interface ListenResult {
  buffer: ListenBuffer;
  /** A finished utterance, pre-roll included, or `null` while one is building. */
  utterance: Uint8Array[] | null;
  reason: EndpointReason | null;
}

/**
 * Effective speech threshold for the audio immediately after `history`.
 *
 * The G2 microphone's level changes dramatically with movement: saved
 * hardware clips contain steady background between 0.5% and 8% of full
 * scale. A fixed threshold either opens on that background or misses quiet
 * speech. The rolling 20th percentile is a cheap noise-floor estimate which
 * remains stable while speech occupies the upper part of the window.
 */
export function adaptiveSpeechThreshold(
  history: readonly EnergySample[],
  minimum: number = SPEECH_RMS,
  percentile: number = NOISE_PERCENTILE,
  multiplier: number = NOISE_MULTIPLIER,
): number {
  if (history.length === 0) return minimum;
  const levels = history.map((sample) => sample.rms).sort((left, right) => left - right);
  const quantile = Math.max(0, Math.min(1, percentile));
  const index = Math.floor((levels.length - 1) * quantile);
  return Math.max(minimum, levels[index]! * multiplier);
}

function appendEnergy(
  history: readonly EnergySample[],
  historyBytes: number,
  sample: EnergySample,
  limit: number,
): { energy: EnergySample[]; bytes: number } {
  const energy = [...history, sample];
  let bytes = historyBytes + sample.bytes;
  while (energy.length > 0 && bytes - energy[0]!.bytes >= limit) {
    bytes -= energy.shift()!.bytes;
  }
  return { energy, bytes };
}

/**
 * Fold one PCM frame in.
 *
 * Closed: the frame joins the pre-roll ring, and a loud frame opens an
 * utterance that *begins with that ring* — this is the lost-syllable fix.
 * Open: the frame extends the utterance until either sustained silence
 * end it or the hard cap does.
 */
export function feedFrame(
  buffer: ListenBuffer,
  frame: Uint8Array,
  options: Partial<ListenOptions> = {},
): ListenResult {
  const limits = { ...LISTEN_DEFAULTS, ...options };
  if (frame.length === 0) return { buffer, utterance: null, reason: null };
  const captured = buffer.captured + frame.length;
  const rms = frameRms(frame);
  const adaptive = adaptiveSpeechThreshold(
    buffer.energy, limits.threshold, limits.noisePercentile, limits.noiseMultiplier,
  );
  // Once the floor is known, quiet commands can pass the adaptive gate. A
  // genuinely strong first word can still start immediately on a fresh mic.
  const threshold = buffer.energyBytes < bytesForMs(NOISE_CALIBRATION_MS)
    ? Math.max(adaptive, STARTUP_SPEECH_RMS) : adaptive;
  const speech = rms >= threshold;
  const observed = appendEnergy(
    buffer.energy, buffer.energyBytes, { rms, bytes: frame.length }, limits.noiseWindowBytes,
  );

  if (!buffer.open) {
    if (!speech) {
      const ring = trimPreroll([...buffer.preroll, frame], limits.prerollBytes);
      return {
        buffer: {
          ...buffer, preroll: ring.frames, prerollBytes: ring.bytes, captured,
          energy: observed.energy, energyBytes: observed.bytes,
        },
        utterance: null, reason: null,
      };
    }
    const utterance = [...buffer.preroll, frame];
    return {
      buffer: {
        preroll: [], prerollBytes: 0, utterance, open: true, trailingSilence: 0, captured,
        utteranceBytes: buffer.prerollBytes + frame.length,
        energy: observed.energy, energyBytes: observed.bytes,
      },
      utterance: null, reason: null,
    };
  }

  const utterance = [...buffer.utterance, frame];
  const utteranceBytes = buffer.utteranceBytes + frame.length;
  const trailingSilence = speech ? 0 : buffer.trailingSilence + frame.length;
  if (trailingSilence >= limits.silenceBytes) {
    return { ...close(utterance, trailingSilence, captured, observed, limits), reason: "silence" };
  }
  if (utteranceBytes >= limits.maxUtteranceBytes) {
    return { ...close(utterance, trailingSilence, captured, observed, limits), reason: "cap" };
  }
  return {
    buffer: {
      ...buffer, utterance, utteranceBytes, trailingSilence, captured,
      energy: observed.energy, energyBytes: observed.bytes,
    },
    utterance: null, reason: null,
  };
}

/**
 * Hand the utterance back with its trailing silence clipped to a short tail,
 * and seed the next pre-roll from what was clipped: the microphone never shut,
 * so that audio is genuinely the run-up to whatever is said next.
 */
function close(
  frames: Uint8Array[],
  trailingSilence: number,
  captured: number,
  observed: { energy: EnergySample[]; bytes: number },
  limits: ListenOptions,
): { buffer: ListenBuffer; utterance: Uint8Array[] } {
  const kept = [...frames];
  const dropped: Uint8Array[] = [];
  let tail = trailingSilence;
  while (kept.length > 0 && tail - kept[kept.length - 1]!.length >= limits.keepTailBytes) {
    const frame = kept.pop()!;
    tail -= frame.length;
    dropped.unshift(frame);
  }
  const ring = trimPreroll(dropped, limits.prerollBytes);
  return {
    buffer: {
      preroll: ring.frames, prerollBytes: ring.bytes, utterance: [], utteranceBytes: 0,
      open: false, trailingSilence: 0, captured,
      energy: observed.energy, energyBytes: observed.bytes,
    },
    utterance: kept,
  };
}
