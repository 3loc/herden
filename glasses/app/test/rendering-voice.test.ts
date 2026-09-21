import assert from "node:assert/strict";
import { test } from "node:test";
import { transcribe } from "../src/stt.ts";
import { LatestFrameRenderer, RenderTimeoutError } from "../src/renderer.ts";
import { OrderedVoiceQueue, processVoiceUtterance } from "../src/voice-pipeline.ts";
import { MicrophoneService } from "../src/microphone-service.ts";
import { EMPTY_LISTEN, SILENCE_END_MS, feedFrame } from "../src/listen.ts";
import type { ListenBuffer } from "../src/listen.ts";
import type { VoiceSession } from "../src/voice-pipeline.ts";

/** 100 ms of unmistakable signed 16-bit speech-like PCM. */
function speech(): Uint8Array {
  const bytes = new Uint8Array(3_200);
  const view = new DataView(bytes.buffer);
  for (let index = 0; index < 1_600; index += 1) {
    view.setInt16(index * 2, index % 2 === 0 ? 12_000 : -12_000, true);
  }
  return bytes;
}

function level(amplitude: number): Uint8Array {
  const frame = new Uint8Array(640); // One 20 ms G2 PCM frame.
  const view = new DataView(frame.buffer);
  const sample = Math.round(amplitude * 0x7fff);
  for (let index = 0; index < 320; index += 1) {
    view.setInt16(index * 2, index % 2 ? -sample : sample, true);
  }
  return frame;
}

test("one continuous mic session accepts two quiet commands without reopening", async () => {
  const controls: boolean[] = [];
  const microphone = new MicrophoneService({
    audioControl: async (enabled) => { controls.push(enabled); return true; },
  });
  const originalFetch = globalThis.fetch;
  const transcripts = ["open two", "go back"];
  const requests: string[] = [];
  globalThis.fetch = (async (input: string | URL | Request) => {
    requests.push(String(input));
    return new Response(JSON.stringify({ text: transcripts.shift() ?? "" }), {
      status: 200, headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;
  const queue = new OrderedVoiceQueue();
  const executed: string[] = [];
  let listen: ListenBuffer = EMPTY_LISTEN;
  const run = (frames: Uint8Array[], session: VoiceSession) => processVoiceUtterance(frames, {
    session,
    transcribe: (wav) => transcribe(wav, { baseUrl: "/stt" }),
    onTranscribing: () => {},
    onResolved: () => {},
    onFailed: (message) => assert.fail(message),
    execute: async (command) => {
      executed.push(command.type === "open" ? `open ${command.position}` : command.type);
    },
    noteActivity: () => {},
  });
  const feed = (amplitude: number, count: number): void => {
    for (let index = 0; index < count; index += 1) {
      const result = feedFrame(listen, level(amplitude));
      listen = result.buffer;
      if (result.utterance) queue.enqueue(result.utterance, run);
    }
  };

  try {
    assert.equal(await microphone.start(), true); // Wake opens the mic.
    queue.start();
    feed(0.04, 250); // Worn-device ambient floor.
    for (let command = 0; command < 2; command += 1) {
      feed(0.095, 30); // Quiet spoken command.
      feed(0.04, SILENCE_END_MS / 20);
    }
    await queue.flush();
    assert.deepEqual(requests, ["/stt/v1/transcribe", "/stt/v1/transcribe"]);
    assert.deepEqual(executed, ["open 2", "back"]);
    assert.deepEqual(controls, [true], "the second command uses the same microphone session");
  } finally {
    queue.stop();
    await microphone.stop();
    globalThis.fetch = originalFetch;
  }
  assert.deepEqual(controls, [true, false]);
});

test("a missing lens callback cannot block STT, parsing, navigation, or later rendering", async () => {
  const writes: string[] = [];
  const rendered: string[] = [];
  const errors: unknown[] = [];
  let rebuilds = 0;
  let first = true;
  const renderer = new LatestFrameRenderer<string>({
    write: (frame) => {
      writes.push(frame);
      if (first) {
        first = false;
        return new Promise<void>(() => {}); // The confirmed G2 SDK failure.
      }
      rendered.push(frame);
      return Promise.resolve();
    },
    rebuild: async () => { rebuilds += 1; },
    timeoutMs: 25,
    onError: (error) => errors.push(error),
  });
  renderer.request("[MIC] listening…");

  const originalFetch = globalThis.fetch;
  const sttRequests: string[] = [];
  globalThis.fetch = (async (input: string | URL | Request) => {
    sttRequests.push(String(input));
    return new Response(JSON.stringify({ text: "open two" }), {
      status: 200, headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;

  const queue = new OrderedVoiceQueue();
  const parsed: string[] = [];
  const navigated: number[] = [];
  queue.start();
  queue.enqueue([speech()], async (frames, session) => {
    await processVoiceUtterance(frames, {
      session,
      transcribe: (wav) => transcribe(wav, { baseUrl: "/stt", timeoutMs: 100 }),
      onTranscribing: () => renderer.request("[MIC] transcribing…"),
      onResolved: (_text, command) => {
        parsed.push(command.type === "open" ? `open ${command.position}` : command.type);
      },
      onFailed: (message) => assert.fail(message),
      execute: async (command) => {
        assert.equal(command.type, "open");
        if (command.type === "open") {
          navigated.push(command.position);
          renderer.request(`opened ${command.position}`);
        }
      },
      noteActivity: () => {},
    });
  });

  try {
    await queue.flush();
  } finally {
    globalThis.fetch = originalFetch;
  }

  // Voice completed while the first display write was still hung.
  assert.deepEqual(sttRequests, ["/stt/v1/transcribe"]);
  assert.deepEqual(parsed, ["open 2"]);
  assert.deepEqual(navigated, [2]);
  assert.deepEqual(writes, ["[MIC] listening…"]);

  await renderer.flush();
  assert.equal(rebuilds, 1);
  assert.ok(errors.some((error) => error instanceof RenderTimeoutError));
  assert.equal(rendered.at(-1), "opened 2", "recovery paints only the latest desired frame");

  renderer.request("later Host update");
  await renderer.flush();
  assert.equal(rendered.at(-1), "later Host update");
});

test("a timed-out write which resumes late cannot leave stale content on the lens", async () => {
  const painted: string[] = [];
  let releaseOld: (() => void) | undefined;
  const oldGate = new Promise<void>((resolve) => { releaseOld = resolve; });
  let first = true;
  const renderer = new LatestFrameRenderer<string>({
    write: async (frame) => {
      if (first) {
        first = false;
        await oldGate;
      }
      painted.push(frame);
    },
    rebuild: async () => {},
    timeoutMs: 10,
  });

  renderer.request("old");
  renderer.request("new");
  await renderer.flush();
  assert.equal(painted.at(-1), "new");

  releaseOld?.();
  await new Promise<void>((resolve) => setTimeout(resolve, 0));
  await renderer.flush();
  assert.deepEqual(painted.slice(-2), ["old", "new"]);
});

test("a native text timeout never rebuilds the page and a later command can render", async () => {
  const writes: string[] = [];
  let first = true;
  const renderer = new LatestFrameRenderer<string>({
    write: async (frame) => {
      writes.push(frame);
      if (first) {
        first = false;
        await new Promise<void>(() => {});
      }
    },
    timeoutMs: 10,
  });

  renderer.request("wake");
  await renderer.flush();
  renderer.request("opened 2");
  await renderer.flush();

  assert.deepEqual(writes, ["wake", "opened 2"]);
});

test("noise and unknown transcripts do not extend idle, but a command does", async () => {
  const session: VoiceSession = { generation: 1, isCurrent: () => true };
  let activity = 0;
  const transcripts = ["background noise", "open two"];
  const executed: string[] = [];
  const run = () => processVoiceUtterance([speech()], {
    session,
    transcribe: async () => transcripts.shift() ?? "",
    onTranscribing: () => {},
    onResolved: () => {},
    onFailed: (message) => assert.fail(message),
    execute: async (command) => {
      executed.push(command.type === "open" ? `open ${command.position}` : command.type);
    },
    noteActivity: () => { activity += 1; },
  });

  await run();
  assert.equal(activity, 0);
  await run();
  assert.equal(activity, 1);
  assert.deepEqual(executed, ["unknown", "open 2"]);
});

test("endpointed commands execute in capture order", async () => {
  const queue = new OrderedVoiceQueue();
  const started: number[] = [];
  const finished: number[] = [];
  let releaseFirst: (() => void) | undefined;
  const firstGate = new Promise<void>((resolve) => { releaseFirst = resolve; });
  const run = async (frames: Uint8Array[]): Promise<void> => {
    const id = frames[0]?.[0] ?? 0;
    started.push(id);
    if (id === 1) await firstGate;
    finished.push(id);
  };

  queue.start();
  queue.enqueue([Uint8Array.of(1)], run);
  queue.enqueue([Uint8Array.of(2)], run);
  await new Promise<void>((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(started, [1]);
  assert.equal(queue.pending, 2);
  releaseFirst?.();
  await queue.flush();
  assert.deepEqual(started, [1, 2]);
  assert.deepEqual(finished, [1, 2]);
  assert.equal(queue.pending, 0);
});

test("stopping the mic invalidates an in-flight result and starts a clean session", async () => {
  const queue = new OrderedVoiceQueue();
  const effects: string[] = [];
  let releaseOld: (() => void) | undefined;
  let oldFinished: (() => void) | undefined;
  const oldGate = new Promise<void>((resolve) => { releaseOld = resolve; });
  const oldDone = new Promise<void>((resolve) => { oldFinished = resolve; });

  queue.start();
  queue.enqueue([Uint8Array.of(1)], async (_frames, session) => {
    await oldGate;
    if (session.isCurrent()) effects.push("stale");
    oldFinished?.();
  });
  await new Promise<void>((resolve) => setTimeout(resolve, 0));
  queue.stop();
  assert.equal(queue.pending, 0);
  releaseOld?.();
  await oldDone;
  assert.deepEqual(effects, []);

  queue.start();
  queue.enqueue([Uint8Array.of(2)], async (_frames, session) => {
    if (session.isCurrent()) effects.push("fresh");
  });
  await queue.flush();
  assert.deepEqual(effects, ["fresh"]);
});

test("sleep aborts an in-flight STT upload and prevents a stale command", async () => {
  const original = globalThis.fetch;
  let uploaded = false;
  let aborted = false;
  globalThis.fetch = ((_input: string | URL | Request, init?: RequestInit) => {
    uploaded = true;
    init?.signal?.addEventListener("abort", () => { aborted = true; });
    return new Promise<Response>(() => {}); // WebView ignores the abort itself.
  }) as typeof fetch;
  const queue = new OrderedVoiceQueue();
  const effects: string[] = [];
  let finished: (() => void) | undefined;
  const done = new Promise<void>((resolve) => { finished = resolve; });
  try {
    queue.start();
    queue.enqueue([speech()], async (frames, session) => {
      try {
        await processVoiceUtterance(frames, {
          session,
          transcribe: (wav, signal) => transcribe(wav, { signal, timeoutMs: 1_000 }),
          onTranscribing: () => {},
          onResolved: () => effects.push("resolved"),
          onFailed: () => effects.push("failed"),
          execute: async () => { effects.push("executed"); },
          noteActivity: () => {},
        });
      } finally { finished?.(); }
    });
    await new Promise<void>((resolve) => setTimeout(resolve, 0));
    assert.equal(uploaded, true);
    queue.stop();
    await done;
    assert.equal(aborted, true);
    assert.deepEqual(effects, []);
  } finally {
    queue.stop();
    globalThis.fetch = original;
  }
});

test("Close stops the current voice session and discards a queued command", async () => {
  const queue = new OrderedVoiceQueue();
  const effects: string[] = [];
  let releaseClose: (() => void) | undefined;
  const closeGate = new Promise<void>((resolve) => { releaseClose = resolve; });
  queue.start();
  const run = async (frames: Uint8Array[], session: VoiceSession): Promise<void> => {
    await processVoiceUtterance(frames, {
      session,
      transcribe: async () => effects.length === 0 ? "Close" : "go to two",
      onTranscribing: () => {},
      onResolved: () => {},
      onFailed: (message) => assert.fail(message),
      execute: async (command) => {
        effects.push(command.type);
        if (command.type === "close") {
          queue.stop();
          await closeGate;
        }
      },
      noteActivity: () => effects.push("activity"),
    });
  };
  queue.enqueue([speech()], run);
  queue.enqueue([speech()], run);
  await new Promise<void>((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(effects, ["close"]);
  assert.equal(queue.open, false);
  assert.equal(queue.pending, 0);
  releaseClose?.();
  await new Promise<void>((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(effects, ["close"]);
});
