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
 * RMS, as a fraction of int16 full scale, above which a frame counts as
 * speech. Glasses-mic room tone measures well below this; conversational
 * speech at the temple measures well above. Tune here if endpointing misses.
 */
export const SPEECH_RMS = 0.02;

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
}

export const LISTEN_DEFAULTS: ListenOptions = {
  prerollBytes: bytesForMs(PREROLL_MS),
  silenceBytes: bytesForMs(SILENCE_END_MS),
  maxUtteranceBytes: bytesForMs(UTTERANCE_MAX_MS),
  keepTailBytes: bytesForMs(TRAILING_SILENCE_KEEP_MS),
  threshold: SPEECH_RMS,
};

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
}

export const EMPTY_LISTEN: ListenBuffer = {
  preroll: [], prerollBytes: 0, utterance: [], utteranceBytes: 0, open: false, trailingSilence: 0, captured: 0,
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
 * Fold one PCM frame in.
 *
 * Closed: the frame joins the pre-roll ring, and a loud frame opens an
 * utterance that *begins with that ring* — this is the lost-syllable fix.
 * Open: the frame extends the utterance until either three seconds of silence
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
  const speech = frameRms(frame) >= limits.threshold;

  if (!buffer.open) {
    if (!speech) {
      const ring = trimPreroll([...buffer.preroll, frame], limits.prerollBytes);
      return {
        buffer: { ...buffer, preroll: ring.frames, prerollBytes: ring.bytes, captured },
        utterance: null, reason: null,
      };
    }
    const utterance = [...buffer.preroll, frame];
    return {
      buffer: {
        preroll: [], prerollBytes: 0, utterance, open: true, trailingSilence: 0, captured,
        utteranceBytes: buffer.prerollBytes + frame.length,
      },
      utterance: null, reason: null,
    };
  }

  const utterance = [...buffer.utterance, frame];
  const utteranceBytes = buffer.utteranceBytes + frame.length;
  const trailingSilence = speech ? 0 : buffer.trailingSilence + frame.length;
  if (trailingSilence >= limits.silenceBytes) {
    return { ...close(utterance, trailingSilence, captured, limits), reason: "silence" };
  }
  if (utteranceBytes >= limits.maxUtteranceBytes) {
    return { ...close(utterance, trailingSilence, captured, limits), reason: "cap" };
  }
  return {
    buffer: { ...buffer, utterance, utteranceBytes, trailingSilence, captured },
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
    },
    utterance: kept,
  };
}
