import assert from "node:assert/strict";
import { test } from "node:test";
import { MIN_CLIP_MS, PCM_FORMAT, WAV_HEADER_BYTES, concatPcm, encodeWav, pcmDurationMs, toPcmBytes } from "../src/audio.ts";
import { describeCommand, dictationSubmission, parseCommand } from "../src/commands.ts";
import {
  IDLE_VOICE, captureAudio, renderVoiceStatus, startListening, stopListening,
  voiceDebugMark, voiceFailed, voiceFooter, voiceIsTransient, voiceResolved,
} from "../src/voice.ts";
import { COLS, ROWS, renderGestureDebug, renderList } from "../src/hud.ts";
import { RESTING_TILT, dueForSleep, initialAttention, observeTilt, wakeProven } from "../src/attention.ts";
import { multipartBody, multipartContentType, transcribe } from "../src/stt.ts";

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
  for (const spoken of ["open 5", "Open five.", "um, open five please", "go to five", "Go to 5."]) {
    assert.deepEqual(parseCommand(spoken), { type: "open", position: 5 }, spoken);
  }
  assert.deepEqual(parseCommand("open twelve"), { type: "open", position: 12 });
});

test("every number word one..twenty is accepted", () => {
  const words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"];
  words.forEach((word, index) => {
    assert.deepEqual(parseCommand(`open ${word}`), { type: "open", position: index + 1 }, word);
    assert.deepEqual(parseCommand(`go to ${word}`), { type: "open", position: index + 1 }, word);
  });
});

test("a homophone counts as a number only after an explicit open", () => {
  assert.deepEqual(parseCommand("open for"), { type: "open", position: 4 });
  assert.deepEqual(parseCommand("open to"), { type: "open", position: 2 });
  assert.deepEqual(parseCommand("for"), { type: "unknown", transcript: "for" });
});

test("going back tolerates the three spoken forms", () => {
  for (const spoken of ["go back", "Go back.", "okay go back please"]) {
    assert.deepEqual(parseCommand(spoken), { type: "back" }, spoken);
  }
});

test("dictation keeps the speaker's text intact instead of applying navigation filler rules", () => {
  assert.deepEqual(parseCommand("Dictate the tests, please."), { type: "dictate", text: "the tests, please." });
  assert.deepEqual(parseCommand("Please dictate: Go back tomorrow."), { type: "dictate", text: "Go back tomorrow." });
  assert.deepEqual(parseCommand("Dictate 你好, world!"), { type: "dictate", text: "你好, world!" });
  assert.deepEqual(parseCommand("dictate"), { type: "unknown", transcript: "dictate" });
});

test("an endpointed dictation types and submits with one Host command", () => {
  const command = parseCommand("Dictate run the tests.");
  assert.equal(command.type, "dictate");
  if (command.type !== "dictate") return;
  assert.deepEqual(dictationSubmission("w1:pT", command.text), {
    action: "send_text", agentId: "w1:pT", text: "run the tests.", submit: true,
  });
});

test("the bottom row reports the recognized voice command without touch instructions", () => {
  const resolved = (text: string) => voiceResolved(IDLE_VOICE, text, describeCommand(parseCommand(text)));
  assert.equal(voiceFooter(IDLE_VOICE, false), "MIC OFF");
  assert.equal(voiceFooter(resolved("go to two"), true), "MIC ON · Go to 2");
  assert.equal(voiceFooter(resolved("go back"), true), "MIC ON · Go back");
  assert.equal(voiceFooter(resolved("page down"), true), "MIC ON · Page down");
  assert.equal(voiceFooter(resolved("close"), true), "MIC ON · Close");
  assert.equal(voiceFooter(resolved("dictate the tests"), true), "MIC ON · Dictate: the tests");
  assert.equal(voiceFooter(resolved("gibberish"), true), "MIC ON · heard gibberish");
});

test("the focused grammar rejects commands outside navigation, dictation, and close", () => {
  for (const spoken of ["5", "five", "space 3", "open row 12", "back", "sleep", "stop listening"]) {
    assert.deepEqual(parseCommand(spoken), { type: "unknown", transcript: spoken }, spoken);
  }
});

test("anything else is unknown and carries the transcript back", () => {
  for (const spoken of ["", "what is the weather", "open the pod bay doors", "open fifty five thousand"]) {
    assert.deepEqual(parseCommand(spoken), { type: "unknown", transcript: spoken.trim() }, spoken);
  }
});

test("each command reads back in the wearer's words", () => {
  assert.equal(describeCommand({ type: "open", position: 7 }), "Go to 7");
  assert.equal(describeCommand({ type: "back" }), "Go back");
  assert.equal(describeCommand({ type: "page", direction: "up" }), "Page up");
  assert.equal(describeCommand({ type: "close" }), "Close");
  assert.equal(describeCommand({ type: "dictate", text: "hello" }), "Dictate: hello");
  assert.equal(describeCommand({ type: "unknown", transcript: "x" }), "not a command");
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
  const rows = renderVoiceStatus(voiceResolved({ phase: "transcribing", captured: 1 }, "go back", "back"));
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
  assert.ok(lines.includes("ev#1 sysEvent type=0"));
  assert.equal(lines.at(-1), "MIC OFF · 30 Spaces");
  assert.ok(lines.length <= ROWS, String(lines.length));
  assert.ok(lines.some((line) => line.startsWith(">30 IDLE Shell")), lines.join("|"));
  assert.equal(renderList(snapshot([agent()]), 0, true).split("\n")[0], ">1 IDLE Shell · host · auth");
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

test("the focused voice commands include paging", () => {
  assert.deepEqual(parseCommand("open two"), { type: "open", position: 2 });
  assert.deepEqual(parseCommand("go to two"), { type: "open", position: 2 });
  assert.deepEqual(parseCommand("go back"), { type: "back" });
  assert.deepEqual(parseCommand("Page up."), { type: "page", direction: "up" });
  assert.deepEqual(parseCommand("page down please"), { type: "page", direction: "down" });
  assert.deepEqual(parseCommand("Close."), { type: "close" });
  assert.deepEqual(parseCommand("please close"), { type: "close" });
  assert.deepEqual(parseCommand("dictate run the tests"), { type: "dictate", text: "run the tests" });
  assert.deepEqual(parseCommand("dictate close"), { type: "dictate", text: "close" });
  assert.deepEqual(parseCommand("dictate page down"), { type: "dictate", text: "page down" });
  assert.deepEqual(parseCommand("back"), { type: "unknown", transcript: "back" });
  assert.deepEqual(parseCommand("wake"), { type: "unknown", transcript: "wake" });
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
  for (const x of [-0.1, -0.1, -0.1, -0.1, -0.1]) tilt = observeTilt(tilt, { x }).state;
  assert.equal(wakeProven(tilt), false);
  tilt = observeTilt(tilt, { x: 1 }).state;
  assert.equal(wakeProven(tilt), true);
  // It stays proven once the head settles again.
  tilt = observeTilt(tilt, { x: -0.1 }).state;
  assert.equal(wakeProven(tilt), true);
});

test("the multipart body is assembled by hand, with the WAV intact", () => {
  const wav = new Uint8Array([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4]);
  const body = Buffer.from(multipartBody(wav, { language: "en" }, "BOUND"));
  const text = body.toString("latin1");
  assert.match(text, /^--BOUND\r\nContent-Disposition: form-data; name="file"; filename="command.wav"\r\nContent-Type: audio\/wav\r\n\r\n/);
  assert.ok(body.includes(Buffer.from(wav)), "the clip bytes survive verbatim");
  assert.match(text, /\r\n--BOUND\r\nContent-Disposition: form-data; name="language"\r\n\r\nen/);
  assert.ok(text.endsWith("\r\n--BOUND--\r\n"));
  assert.equal(multipartContentType("BOUND"), "multipart/form-data; boundary=BOUND");
});

test("a transcription that never answers fails instead of wedging the queue", async () => {
  const hang = new Promise<Response>(() => {});
  const original = globalThis.fetch;
  globalThis.fetch = (() => hang) as typeof fetch;
  try {
    await assert.rejects(
      transcribe(new Uint8Array([1, 2, 3]), { timeoutMs: 20 }),
      /timed out/,
    );
  } finally {
    globalThis.fetch = original;
  }
});

test("a response whose JSON body never settles obeys the same STT deadline", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (async () => ({
    ok: true,
    json: () => new Promise<unknown>(() => {}),
  })) as typeof fetch;
  try {
    await assert.rejects(
      transcribe(new Uint8Array([1, 2, 3]), { timeoutMs: 20 }),
      /timed out/,
    );
  } finally {
    globalThis.fetch = original;
  }
});

test("STT cancellation settles even when the WebView ignores fetch abort", async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = (() => {
    calls += 1;
    return new Promise<Response>(() => {});
  }) as typeof fetch;
  try {
    const alreadyAborted = new AbortController();
    alreadyAborted.abort();
    await assert.rejects(
      transcribe(new Uint8Array([1]), { signal: alreadyAborted.signal }),
      { name: "AbortError" },
    );
    assert.equal(calls, 0, "an expired session must not upload audio");

    const controller = new AbortController();
    const pending = transcribe(new Uint8Array([1]), { signal: controller.signal, timeoutMs: 1_000 });
    controller.abort();
    await assert.rejects(pending, { name: "AbortError" });
    assert.equal(calls, 1);
  } finally {
    globalThis.fetch = original;
  }
});
