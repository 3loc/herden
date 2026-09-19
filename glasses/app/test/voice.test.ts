import assert from "node:assert/strict";
import { test } from "node:test";
import { MIN_CLIP_MS, PCM_FORMAT, WAV_HEADER_BYTES, concatPcm, encodeWav, pcmDurationMs, toPcmBytes } from "../src/audio.ts";
import { describeCommand, parseCommand } from "../src/commands.ts";
import {
  IDLE_VOICE, captureAudio, renderVoiceStatus, startListening, stopListening,
  voiceDebugMark, voiceFailed, voiceIsTransient, voiceResolved,
} from "../src/voice.ts";
import { COLS, renderGestureDebug, renderList } from "../src/hud.ts";
import { RESTING_TILT, dueForSleep, initialAttention, observeTilt, wakeProven } from "../src/attention.ts";

import type { Agent, Snapshot } from "../src/protocol.ts";

const text = (bytes: Uint8Array, at: number, length: number): string =>
  String.fromCharCode(...bytes.slice(at, at + length));
const u32 = (bytes: Uint8Array, at: number): number => new DataView(bytes.buffer, bytes.byteOffset).getUint32(at, true);
const u16 = (bytes: Uint8Array, at: number): number => new DataView(bytes.buffer, bytes.byteOffset).getUint16(at, true);

test("the WAV header describes the assumed glasses PCM format", () => {
  const pcm = new Uint8Array(1000);
  const wav = encodeWav([pcm]);
  assert.equal(text(wav, 0, 4), "RIFF");
  assert.equal(text(wav, 8, 4), "WAVE");
  assert.equal(text(wav, 12, 4), "fmt ");
  assert.equal(u32(wav, 16), 16); // PCM fmt chunk length.
  assert.equal(u16(wav, 20), 1); // Uncompressed PCM.
  assert.equal(u16(wav, 22), 1); // Mono.
  assert.equal(u32(wav, 24), 16_000);
  assert.equal(u32(wav, 28), 32_000); // Byte rate: 16 kHz × 2 bytes.
  assert.equal(u16(wav, 32), 2); // Block align.
  assert.equal(u16(wav, 34), 16); // Bits per sample.
  assert.equal(text(wav, 36, 4), "data");
  assert.equal(u32(wav, 40), pcm.length);
  assert.equal(u32(wav, 4), 36 + pcm.length);
  assert.equal(wav.length, WAV_HEADER_BYTES + pcm.length);
  assert.deepEqual(PCM_FORMAT, { sampleRate: 16_000, channels: 1, bitsPerSample: 16 });
});

test("the captured frames follow the header in order", () => {
  const wav = encodeWav([Uint8Array.of(1, 2), Uint8Array.of(3, 4), Uint8Array.of(5, 6)]);
  assert.equal(u32(wav, 40), 6);
  assert.deepEqual([...wav.slice(WAV_HEADER_BYTES)], [1, 2, 3, 4, 5, 6]);
  assert.deepEqual([...concatPcm([])], []);
  // An empty clip still produces a structurally valid file.
  assert.equal(encodeWav([]).length, WAV_HEADER_BYTES);
  assert.equal(u32(encodeWav([]), 40), 0);
});

test("PCM arrives as bytes, as numbers or as base64, and never throws", () => {
  assert.deepEqual([...toPcmBytes(Uint8Array.of(7, 8))], [7, 8]);
  assert.deepEqual([...toPcmBytes([7, 8])], [7, 8]);
  assert.deepEqual([...toPcmBytes("AQI=")], [1, 2]);
  assert.deepEqual([...toPcmBytes(undefined)], []);
  assert.deepEqual([...toPcmBytes({ nope: true })], []);
});

test("clip length follows the assumed sample rate", () => {
  assert.equal(pcmDurationMs(32_000), 1000);
  assert.equal(pcmDurationMs(3_200), 100);
  assert.ok(pcmDurationMs(1_000) < MIN_CLIP_MS);
});

test("the grammar opens a Space by its visible position", () => {
  for (const spoken of ["open 5", "Open five.", "open space 5", "open space five", "5", "five", "  FIVE!  ", "um, open five please"]) {
    assert.deepEqual(parseCommand(spoken), { type: "open", position: 5 }, spoken);
  }
  assert.deepEqual(parseCommand("open row 12"), { type: "open", position: 12 });
  assert.deepEqual(parseCommand("space 3"), { type: "open", position: 3 });
});

test("every number word one..twenty is accepted", () => {
  const words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"];
  words.forEach((word, index) => {
    assert.deepEqual(parseCommand(`open ${word}`), { type: "open", position: index + 1 }, word);
    assert.deepEqual(parseCommand(word), { type: "open", position: index + 1 }, word);
    assert.deepEqual(parseCommand(String(index + 1)), { type: "open", position: index + 1 });
  });
});

test("a homophone counts as a number only after an explicit open", () => {
  assert.deepEqual(parseCommand("open for"), { type: "open", position: 4 });
  assert.deepEqual(parseCommand("open to"), { type: "open", position: 2 });
  assert.deepEqual(parseCommand("for"), { type: "unknown", transcript: "for" });
});

test("going back tolerates the three spoken forms", () => {
  for (const spoken of ["go back", "Go back.", "back", "Back!", "close", "okay go back please"]) {
    assert.deepEqual(parseCommand(spoken), { type: "back" }, spoken);
  }
});

test("dictation keeps its text verbatim, punctuation and all", () => {
  assert.deepEqual(parseCommand("dictate run the tests again"), { type: "dictate", text: "run the tests again" });
  assert.deepEqual(parseCommand("Dictate: Fix the login bug, please."), { type: "dictate", text: "Fix the login bug, please." });
  assert.deepEqual(parseCommand("type hello world"), { type: "dictate", text: "hello world" });
  // With nothing to dictate it is not a dictation command.
  assert.deepEqual(parseCommand("dictate"), { type: "unknown", transcript: "dictate" });
});

test("anything else is unknown and carries the transcript back", () => {
  for (const spoken of ["", "what is the weather", "open the pod bay doors", "open fifty five thousand"]) {
    assert.deepEqual(parseCommand(spoken), { type: "unknown", transcript: spoken.trim() }, spoken);
  }
});

test("each command reads back in the wearer's words", () => {
  assert.equal(describeCommand({ type: "open", position: 7 }), "open 7");
  assert.equal(describeCommand({ type: "back" }), "back");
  assert.equal(describeCommand({ type: "unknown", transcript: "x" }), "not a command");
  // Dictation has no Host write path; the lens says so with the heard text.
  assert.equal(describeCommand({ type: "dictate", text: "ship it" }), 'dictation needs Host support: "ship it"');
});

test("a press listens, captures and transcribes", () => {
  const pressed = startListening(IDLE_VOICE);
  assert.equal(pressed.openMic, true);
  assert.equal(pressed.state.phase, "listening");
  const captured = captureAudio(pressed.state, 32_000);
  assert.equal(captured.captured, 32_000);
  const released = stopListening(captured);
  assert.deepEqual(
    { phase: released.state.phase, closeMic: released.closeMic, transcribe: released.transcribe },
    { phase: "transcribing", closeMic: true, transcribe: true },
  );
});

test("a second press does not reopen an already-open mic", () => {
  const listening = captureAudio(startListening(IDLE_VOICE).state, 500);
  const again = startListening(listening);
  assert.equal(again.openMic, false);
  assert.equal(again.state, listening); // Nothing captured so far is lost.
});

test("a release with no audio fails loudly and still closes the mic", () => {
  const released = stopListening(startListening(IDLE_VOICE).state);
  assert.equal(released.state.phase, "error");
  assert.equal(released.closeMic, true);
  assert.equal(released.transcribe, false);
  assert.match(renderVoiceStatus(released.state)[0]!, /no audio/);
});

test("a clip too short to be speech is not sent for transcription", () => {
  const brief = captureAudio(startListening(IDLE_VOICE).state, 1_000); // ~31 ms.
  const released = stopListening(brief);
  assert.equal(released.state.phase, "error");
  assert.equal(released.closeMic, true);
  assert.equal(released.transcribe, false);
  assert.match(renderVoiceStatus(released.state)[0]!, /too short/);
});

test("a release outside a press is inert rather than stuck", () => {
  for (const state of [IDLE_VOICE, { phase: "transcribing" as const, captured: 10 }]) {
    const released = stopListening(state);
    assert.equal(released.transcribe, false);
    assert.equal(released.closeMic, false);
    assert.equal(released.state, state);
  }
  // Frames outside a press belong to nothing.
  assert.equal(captureAudio(IDLE_VOICE, 4_000).captured, 0);
});

test("a failed transcription leaves the error on the lens, never listening", () => {
  const failed = voiceFailed({ phase: "transcribing", captured: 32_000 }, "transcribe failed: 503");
  assert.equal(failed.phase, "error");
  assert.deepEqual(renderVoiceStatus(failed), ["[MIC] transcribe failed: 503"]);
  assert.ok(voiceIsTransient(failed));
  assert.ok(!voiceIsTransient(IDLE_VOICE));
  assert.ok(!voiceIsTransient({ phase: "listening", captured: 0 }));
  // A misheard command keeps its transcript beside the failure.
  const missed = voiceFailed({ phase: "result", captured: 1, transcript: "open nine" }, "no Space 9 on the lens");
  assert.deepEqual(renderVoiceStatus(missed), ['[MIC] "open nine"', "! no Space 9 on the lens"]);
});

test("the lens states listening, transcribing and what was resolved", () => {
  assert.deepEqual(renderVoiceStatus(IDLE_VOICE), []);
  assert.deepEqual(renderVoiceStatus({ phase: "listening", captured: 0 }), ["[MIC] listening…"]);
  assert.deepEqual(renderVoiceStatus({ phase: "transcribing", captured: 64_000 }), ["[MIC] transcribing…"]);
  assert.deepEqual(
    renderVoiceStatus(voiceResolved({ phase: "transcribing", captured: 1 }, "open five", "open 5")),
    ['[MIC] "open five" → open 5'],
  );
  // A long read-back wraps to a second row rather than losing the outcome.
  const dictation = voiceResolved({ phase: "transcribing", captured: 1 }, "dictate run the whole test suite again", 'dictation needs Host support: "run the whole test suite again"');
  const rows = renderVoiceStatus(dictation);
  assert.equal(rows.length, 2);
  assert.match(rows[1]!, /^→ dictation needs Host support/);
  for (const row of [...rows, ...renderVoiceStatus({ phase: "error", captured: 0, message: "x".repeat(200) })]) {
    assert.ok(row.length <= COLS, row);
  }
});

const agent = (over: Partial<Agent> = {}): Agent => ({ id: "w1:pT", name: "auth", space: "herden", status: "idle", pinned: false, ...over });
const snapshot = (agents: Agent[]): Snapshot => ({
  protocol_version: 1, type: "snapshot", revision: 1, at: 0, inventory_valid: true,
  stale: false, controls_allowed: false, agents, wake: [], summary: "",
});

test("the microphone row sits above the Spaces without overflowing the lens", () => {
  const many = Array.from({ length: 30 }, (_, index) => agent({ id: `w${index}`, name: `space-${index}` }));
  const lines = renderList(snapshot(many), 29, true, "no agents", "ev#1 sysEvent type=0", ["[MIC] listening…"]).split("\n");
  assert.equal(lines[0], "[MIC] listening…");
  assert.equal(lines.at(-1), "ev#1 sysEvent type=0");
  assert.ok(lines.length <= 20, String(lines.length));
  assert.ok(lines.some((line) => line.startsWith(">30[I]")), lines.join("|"));
  // No microphone rows: the list renders exactly as it did before.
  assert.equal(renderList(snapshot([agent()]), 0, true), "> 1[I][Zsh][host]:auth");
});

test("the diagnostic row also reports the mic state and last transcript", () => {
  assert.equal(voiceDebugMark(IDLE_VOICE), "idle");
  assert.equal(voiceDebugMark({ phase: "listening", captured: 0 }), "listening");
  assert.equal(
    renderGestureDebug({ count: 2, field: "sysEvent", eventType: 9, mic: "listening" }),
    "ev#2 sysEvent type=9 mic=listening",
  );
  assert.equal(
    renderGestureDebug({ count: 3, field: "sysEvent", eventType: 10, mic: "result", transcript: "open five" }),
    'ev#3 sysEvent type=10 mic=result "open five"',
  );
  assert.ok(renderGestureDebug({ count: 4, field: "sysEvent", mic: "result", transcript: "x".repeat(200) }).length <= COLS);
});

test("the spoken forms of ending a session all reach sleep", () => {
  for (const said of ["sleep", "go to sleep", "Sleep.", "stop", "stop listening", "stop listen", "please sleep"]) {
    assert.deepEqual(parseCommand(said), { type: "sleep" }, said);
  }
  assert.equal(describeCommand({ type: "sleep" }), "sleep");
  // Waking is the tilt and the long press; it is never spoken at a dark lens.
  assert.deepEqual(parseCommand("wake"), { type: "unknown", transcript: "wake" });
  // The existing grammar is untouched by the new verbs.
  assert.deepEqual(parseCommand("open two"), { type: "open", position: 2 });
  assert.deepEqual(parseCommand("back"), { type: "back" });
});

test("a lens never sleeps until a tilt wake has actually been seen", () => {
  const awake = initialAttention(0);
  // 60 s of nothing, but the tilt gesture has never fired on this hardware.
  assert.equal(dueForSleep(awake, 60_000, 15_000, 180_000, false), null);
  assert.equal(dueForSleep(awake, 60_000, 15_000, 180_000, true), "idle");
});

test("observing a raise marks the wake gesture as proven", () => {
  let tilt = RESTING_TILT;
  assert.equal(wakeProven(tilt), false);
  for (const y of [0, 0, 0, 0, 0]) tilt = observeTilt(tilt, { y }).state;
  assert.equal(wakeProven(tilt), false);
  tilt = observeTilt(tilt, { y: 1 }).state;
  assert.equal(wakeProven(tilt), true);
  // It stays proven once the head settles again.
  tilt = observeTilt(tilt, { y: 0 }).state;
  assert.equal(wakeProven(tilt), true);
});
