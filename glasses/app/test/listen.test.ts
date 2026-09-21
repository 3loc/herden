import assert from "node:assert/strict";
import { test } from "node:test";
import {
  EMPTY_LISTEN, NOISE_MULTIPLIER, PREROLL_MS, SILENCE_END_MS, SPEECH_RMS,
  TRAILING_SILENCE_KEEP_MS, UTTERANCE_MAX_MS, adaptiveSpeechThreshold,
  bytesForMs, containsSpeech, feedFrame, frameRms, trimPreroll,
} from "../src/listen.ts";
import type { ListenBuffer } from "../src/listen.ts";
import { pcmDurationMs } from "../src/audio.ts";

/** One 20 ms frame of signed 16-bit mono PCM at the given amplitude, 0…1. */
function frame(amplitude: number, ms = 20): Uint8Array {
  const samples = Math.round((ms / 1000) * 16_000);
  const bytes = new Uint8Array(samples * 2);
  const view = new DataView(bytes.buffer);
  const peak = Math.round(amplitude * 0x7fff);
  // A square wave, so RMS is exactly the amplitude — no threshold guesswork.
  for (let index = 0; index < samples; index += 1) view.setInt16(index * 2, index % 2 === 0 ? peak : -peak, true);
  return bytes;
}

const SILENT = 0.001;
const LOUD = SPEECH_RMS * 5;
const FRAME_MS = 20;
const silence = (): Uint8Array => frame(SILENT, FRAME_MS);
const speech = (): Uint8Array => frame(LOUD, FRAME_MS);

function feed(buffer: ListenBuffer, frames: Uint8Array[]): { buffer: ListenBuffer; utterances: Uint8Array[][]; reasons: string[] } {
  const utterances: Uint8Array[][] = [];
  const reasons: string[] = [];
  let current = buffer;
  for (const one of frames) {
    const result = feedFrame(current, one);
    current = result.buffer;
    if (result.utterance) { utterances.push(result.utterance); reasons.push(result.reason ?? ""); }
  }
  return { buffer: current, utterances, reasons };
}

const bytes = (frames: readonly Uint8Array[]): number => frames.reduce((sum, one) => sum + one.length, 0);
const repeat = (make: () => Uint8Array, count: number): Uint8Array[] => Array.from({ length: count }, make);

test("energy separates room tone from speech at the configured threshold", () => {
  assert.ok(frameRms(silence()) < SPEECH_RMS);
  assert.ok(frameRms(speech()) >= SPEECH_RMS);
  assert.equal(frameRms(new Uint8Array(0)), 0);
  assert.ok(!containsSpeech(repeat(silence, 50)));
  assert.ok(containsSpeech([...repeat(silence, 50), speech()]));
});

test("the speech threshold follows a sustained noise floor", () => {
  const history = [0.057, 0.061, 0.059, 0.24, 0.063].map((rms) => ({ rms, bytes: frame(rms).length }));
  const threshold = adaptiveSpeechThreshold(history);
  assert.ok(threshold >= 0.057 * NOISE_MULTIPLIER, String(threshold));
  assert.ok(threshold < 0.24, String(threshold));
});

test("quiet speech above a noisy worn-G2 floor closes after 1.2 seconds of silence", () => {
  // Recent hardware clips had ~4% background RMS and speech around 9–10%.
  // The old 3× gate missed that speech and ran to the 15-second cap.
  const ambient = (): Uint8Array => frame(0.04);
  const quietSpeech = (): Uint8Array => frame(0.095);
  const calibrated = feed(EMPTY_LISTEN, repeat(ambient, 250));
  assert.equal(calibrated.buffer.open, false);
  const speaking = feed(calibrated.buffer, repeat(quietSpeech, 30));
  assert.equal(speaking.buffer.open, true, "quiet words must open the utterance");
  const nearly = feed(speaking.buffer, repeat(ambient, 59));
  assert.equal(nearly.utterances.length, 0);
  const ended = feed(nearly.buffer, [ambient()]);
  assert.deepEqual(ended.reasons, ["silence"]);
  assert.equal(ended.buffer.open, false);
  assert.ok(pcmDurationMs(bytes(ended.utterances[0]!)) < UTTERANCE_MAX_MS);
});

test("the first ambient mic frames calibrate without becoming a false command", () => {
  const ambient = (): Uint8Array => frame(0.04);
  const calibrated = feed(EMPTY_LISTEN, repeat(ambient, 30));
  assert.equal(calibrated.buffer.open, false);
  assert.equal(calibrated.utterances.length, 0);
  assert.equal(feedFrame(calibrated.buffer, frame(0.095)).buffer.open, true);
  // A clearly spoken first word still starts without waiting for calibration.
  assert.equal(feedFrame(EMPTY_LISTEN, frame(0.15)).buffer.open, true);
});

// ---------------------------------------------------------------------------
// Pre-roll: the lost-first-syllable fix
// ---------------------------------------------------------------------------

test("the pre-roll ring keeps at least the configured window and drops the rest", () => {
  const limit = bytesForMs(PREROLL_MS);
  const ring = trimPreroll(repeat(silence, 200), limit);
  assert.ok(ring.bytes >= limit, `${ring.bytes} < ${limit}`);
  // Retention is a floor, not a target: never more than one frame of slack.
  assert.ok(ring.bytes - limit < ring.frames[0]!.length, String(ring.bytes - limit));
  assert.equal(ring.bytes, bytes(ring.frames));
  // A ring shorter than the window is left whole.
  const short = trimPreroll(repeat(silence, 3), limit);
  assert.equal(short.frames.length, 3);
});

test("the pre-roll window is at least half a second of audio", () => {
  assert.ok(PREROLL_MS >= 500, String(PREROLL_MS));
  assert.equal(pcmDurationMs(bytesForMs(PREROLL_MS)), PREROLL_MS);
});

test("an utterance starts before the first loud frame, never on it", () => {
  // Continuous capture: a minute of room tone precedes the phrase.
  const before = feed(EMPTY_LISTEN, repeat(silence, 3_000));
  assert.equal(before.utterances.length, 0);
  assert.ok(before.buffer.prerollBytes >= bytesForMs(PREROLL_MS));
  const opened = feedFrame(before.buffer, speech());
  assert.equal(opened.utterance, null);
  assert.ok(opened.buffer.open);
  // The whole pre-roll was carried into the utterance, ahead of the loud
  // frame. This is the bug: push-to-talk started here and lost the syllable.
  assert.equal(opened.buffer.utteranceBytes, before.buffer.prerollBytes + speech().length);
  assert.ok(pcmDurationMs(opened.buffer.utteranceBytes) >= PREROLL_MS);
  assert.equal(opened.buffer.prerollBytes, 0);
  assert.deepEqual(opened.buffer.preroll, []);
});

// ---------------------------------------------------------------------------
// Endpointing
// ---------------------------------------------------------------------------

test("configured silence ends the utterance, and not a frame sooner", () => {
  const frames = Math.round(SILENCE_END_MS / FRAME_MS);
  const opened = feed(EMPTY_LISTEN, [...repeat(silence, 10), ...repeat(speech, 25)]).buffer;
  const nearly = feed(opened, repeat(silence, frames - 1));
  assert.equal(nearly.utterances.length, 0, "ended before three seconds of silence");
  assert.ok(nearly.buffer.open);
  const ended = feedFrame(nearly.buffer, silence());
  assert.equal(ended.reason, "silence");
  assert.ok(ended.utterance);
  assert.equal(ended.buffer.open, false);
  // The utterance holds the pre-roll, the speech and a short tail only.
  const utterance = ended.utterance ?? [];
  assert.ok(containsSpeech(utterance));
  const kept = pcmDurationMs(bytes(utterance));
  const spoken = PREROLL_MS + 25 * FRAME_MS;
  assert.ok(kept >= spoken, `${kept} < ${spoken}`);
  assert.ok(kept <= spoken + TRAILING_SILENCE_KEEP_MS + FRAME_MS, String(kept));
});

test("rising background noise does not hold an utterance open", () => {
  const ambient = (): Uint8Array => frame(0.06, FRAME_MS);
  const clearSpeech = (): Uint8Array => frame(0.3, FRAME_MS);
  // Calibrate on the louder room before speech. This is the shape of the G2
  // hardware regression: 6% background sat above the old fixed 2% threshold.
  const calibrated = feed(EMPTY_LISTEN, repeat(ambient, 250));
  assert.equal(calibrated.buffer.open, false);
  const phrase = feed(calibrated.buffer, repeat(clearSpeech, 25));
  assert.ok(phrase.buffer.open);
  const ended = feed(phrase.buffer, repeat(ambient, Math.round(SILENCE_END_MS / FRAME_MS)));
  assert.equal(ended.utterances.length, 1);
  assert.equal(ended.reasons[0], "silence");
});

test("the next phrase gets a pre-roll from the silence that ended the last", () => {
  const first = feed(EMPTY_LISTEN, [
    ...repeat(silence, 50), ...repeat(speech, 25), ...repeat(silence, Math.round(SILENCE_END_MS / FRAME_MS)),
  ]);
  assert.equal(first.utterances.length, 1);
  // The microphone never shut, so that trailing audio really is the run-up.
  assert.ok(first.buffer.prerollBytes >= bytesForMs(PREROLL_MS), String(first.buffer.prerollBytes));
  const second = feedFrame(first.buffer, speech());
  assert.ok(pcmDurationMs(second.buffer.utteranceBytes) >= PREROLL_MS);
});

test("a monologue is cut at the hard cap rather than growing forever", () => {
  const frames = Math.round((UTTERANCE_MAX_MS * 2) / FRAME_MS);
  // Real speech has low-energy consonants between its peaks. A perfectly
  // constant tone is intentionally learned as background by the adaptive
  // floor, so model a continuous voice rather than a laboratory square wave.
  const talked = feed(EMPTY_LISTEN, Array.from(
    { length: frames }, (_, index) => frame(index % 2 === 0 ? 0.04 : 0.3, FRAME_MS),
  ));
  assert.ok(talked.utterances.length >= 2, String(talked.utterances.length));
  assert.deepEqual([...new Set(talked.reasons)], ["cap"]);
  for (const utterance of talked.utterances) {
    const length = pcmDurationMs(bytes(utterance));
    assert.ok(length <= UTTERANCE_MAX_MS + FRAME_MS, String(length));
  }
});

test("pure silence never becomes an utterance, however long it runs", () => {
  // parakeet hallucinates words onto silence, so nothing may be sent.
  const quiet = feed(EMPTY_LISTEN, repeat(silence, Math.round((UTTERANCE_MAX_MS * 3) / FRAME_MS)));
  assert.deepEqual(quiet.utterances, []);
  assert.equal(quiet.buffer.open, false);
  // And the ring stays bounded through the whole of it.
  assert.ok(quiet.buffer.prerollBytes < bytesForMs(PREROLL_MS) + silence().length);
});

test("an empty frame is inert and capture counts every byte it does take", () => {
  const empty = feedFrame(EMPTY_LISTEN, new Uint8Array(0));
  assert.deepEqual(empty.buffer, EMPTY_LISTEN);
  const fed = feed(EMPTY_LISTEN, repeat(silence, 5));
  assert.equal(fed.buffer.captured, 5 * silence().length);
});
