import assert from "node:assert/strict";
import { test } from "node:test";
import { HudModel, mergeSnapshots } from "../src/hud-model.ts";
import { outputWindowSize, renderDetail } from "../src/hud.ts";
import { NativeLensView } from "../src/lens-view.ts";
import type { LensBridge } from "../src/lens-view.ts";
import { MicrophoneService } from "../src/microphone-service.ts";
import type { AudioBridge } from "../src/microphone-service.ts";
import { HostService } from "../src/host-service.ts";
import type { ClientOptions } from "../src/client.ts";
import type { Agent, HostSettings, Snapshot } from "../src/protocol.ts";

const hosts: HostSettings[] = [
  { id: "one", name: "host-a", baseUrl: "/one", token: "secret" },
  { id: "two", name: "host-b", baseUrl: "/two", token: "secret" },
];
const agent = (id: string, status: Agent["status"] = "idle"): Agent => ({
  id, name: id, space: id, status, pinned: false,
});
const snapshot = (agents: Agent[], revision = 1): Snapshot => ({
  protocol_version: 1, type: "snapshot", revision, at: 0,
  inventory_valid: true, stale: false, controls_allowed: true,
  agents, wake: agents.map((item) => item.id), summary: "test",
});

test("model merges Hosts, preserves opaque remote IDs, and projects hidden Spaces", () => {
  const sources = new Map([
    ["one", snapshot([agent("w1:pT")])],
    ["two", snapshot([agent("wR:pC", "blocked")], 4)],
  ]);
  const merged = mergeSnapshots(hosts, sources);
  assert.deepEqual(merged?.agents.map((item) => item.id), ["two:wR:pC", "one:w1:pT"]);
  assert.deepEqual(merged?.wake, ["one:w1:pT", "two:wR:pC"]);
  assert.equal(merged?.revision, 4);
  assert.equal(merged?.agents[0]?.remoteId, "wR:pC");

  const model = new HudModel(0);
  model.hosts = hosts;
  model.refresh(sources, new Set(["one"]), new Set(["two:wR:pC"]));
  assert.equal(model.roster?.agents.length, 2);
  assert.deepEqual(model.snapshot?.agents.map((item) => item.id), ["one:w1:pT"]);
  assert.equal(model.online, true);
});

test("model preserves selected identity across reordered snapshots and invalidates stale reads", () => {
  const model = new HudModel(0);
  model.hosts = hosts;
  const sources = new Map([["one", snapshot([agent("a"), agent("b")])]]);
  model.refresh(sources, new Set(["one"]), new Set());
  assert.equal(model.selectPosition(2), true);
  assert.equal(model.selectPosition(3), false);
  assert.equal(model.selectedAgent()?.id, "one:b");
  sources.set("one", snapshot([agent("b", "blocked"), agent("a")], 2));
  model.refresh(sources, new Set(["one"]), new Set());
  assert.equal(model.selectedAgent()?.id, "one:b");
  const request = model.beginOutput();
  model.setOutput(["first", "second"]);
  assert.equal(model.view, "detail");
  model.showList();
  assert.ok(model.outputRequest > request);
  assert.equal(model.outputLoading, false);
  assert.equal(model.view, "list");
});

test("opening a long Space starts at the newest output, above the fixed status row", () => {
  const model = new HudModel(0);
  model.snapshot = snapshot([agent("space")]);
  const lines = Array.from({ length: 20 }, (_, index) => `line ${index + 1}`);
  model.setOutput(lines);
  assert.equal(model.outputOffset, lines.length - outputWindowSize());
  const frame = renderDetail(model.selectedAgent()!, model.output, model.outputOffset, true);
  assert.equal(frame.split("\n")[1], "line 13");
  assert.equal(frame.split("\n")[8], "line 20");
  assert.match(frame.split("\n")[9]!, /20\/20/);
});

test("live terminal output follows the bottom but preserves a deliberate scrollback", () => {
  const model = new HudModel(0);
  model.setOutput(Array.from({ length: 12 }, (_, index) => `line ${index + 1}`));
  assert.equal(model.outputOffset, 4);
  assert.equal(model.updateOutput([...model.output, "line 13"]), true);
  assert.equal(model.outputOffset, 5);
  model.scroll(-1);
  assert.equal(model.outputOffset, 4);
  assert.equal(model.updateOutput([...model.output, "line 14"]), true);
  assert.equal(model.outputOffset, 4);
  assert.equal(model.updateOutput([...model.output]), false);
});

test("Page up and Page down move by screenfuls in both views", () => {
  const model = new HudModel(0);
  model.snapshot = snapshot(Array.from({ length: 30 }, (_, index) => agent(`space-${index + 1}`)));
  model.page(1);
  assert.equal(model.selected, 8);
  model.page(1);
  assert.equal(model.selected, 16);
  model.page(-1);
  assert.equal(model.selected, 8);
  model.selectPosition(30);
  model.page(1);
  assert.equal(model.selected, 29);

  model.setOutput(Array.from({ length: 30 }, (_, index) => `line ${index + 1}`));
  assert.equal(model.outputOffset, 22);
  model.page(-1);
  assert.equal(model.outputOffset, 14);
  model.page(-1);
  assert.equal(model.outputOffset, 6);
  model.page(-1);
  assert.equal(model.outputOffset, 0);
  model.page(1);
  assert.equal(model.outputOffset, 8);
  model.showList();
  model.setOutput(Array.from({ length: 30 }, (_, index) => `line ${index + 1}`));
  assert.equal(model.outputOffset, 22, "reopening always resets to the newest output");
});

test("Host service rejects callbacks from replaced connections", async () => {
  const options: ClientOptions[] = [];
  const disconnected: number[] = [];
  const sent: { client: number; submit: boolean | undefined }[] = [];
  let changes = 0;
  const service = new HostService({
    onChange: () => { changes += 1; },
    clientFactory: (clientOptions) => {
      const index = options.push(clientOptions) - 1;
      return {
        online: false,
        connect: () => {},
        disconnect: () => { disconnected.push(index); },
        readOutput: async (agentId) => ({ agent_id: agentId, text: "ok", source: "recent" }),
        send: async (command) => {
          sent.push({ client: index, submit: command.action === "send_text" ? command.submit : undefined });
          return true;
        },
      };
    },
  });
  service.connect([hosts[0]!]);
  assert.equal(await service.sendCommand("one", { action: "send_text", agentId: "w1:pT", text: "hello", submit: true }), true);
  assert.deepEqual(sent, [{ client: 0, submit: true }]);
  options[0]?.onSnapshot(snapshot([agent("old")]));
  assert.equal(service.snapshots.get("one")?.agents[0]?.id, "old");
  service.connect([hosts[1]!]);
  assert.equal(await service.sendCommand("one", { action: "send_enter", agentId: "w1:pT" }), false);
  assert.deepEqual(disconnected, [0]);
  assert.equal(service.snapshots.has("one"), false);
  const beforeStale = changes;
  options[0]?.onSnapshot(snapshot([agent("stale")]));
  options[0]?.onConnectionChange?.(true);
  assert.equal(changes, beforeStale);
  assert.equal(service.snapshots.size, 0);
  assert.equal(service.onlineHosts.size, 0);
  options[1]?.onConnectionChange?.(true);
  options[1]?.onSnapshot(snapshot([agent("current")]));
  assert.equal(service.onlineHosts.has("two"), true);
  assert.equal(service.snapshots.get("two")?.agents[0]?.id, "current");
});

test("native lens creates one firmware text container and updates without image painting", async () => {
  const calls: { method: string; value: unknown }[] = [];
  const bridge = {
    createStartUpPageContainer: async (value: unknown) => { calls.push({ method: "create", value }); return 0; },
    rebuildPageContainer: async (value: unknown) => { calls.push({ method: "rebuild", value }); return true; },
    textContainerUpgrade: async (value: unknown) => { calls.push({ method: "text", value }); return true; },
  } as unknown as LensBridge;
  const view = new NativeLensView(bridge);
  await view.initialize();
  view.show("Space 1");
  await view.flush();
  view.show("");
  await view.flush();
  assert.deepEqual(calls.map((call) => call.method), ["create", "text", "text"]);
  assert.equal((calls[0]?.value as { containerTotalNum?: number }).containerTotalNum, 1);
  assert.equal((calls[1]?.value as { content?: string }).content, "Space 1");
  assert.equal((calls[2]?.value as { content?: string }).content, " ");
});

test("invalid, oversize, and OOM startup results never trigger a page rebuild", async () => {
  for (const [result, label] of [[1, "invalid container"], [2, "oversize"], [3, "out of memory"]] as const) {
    let rebuilds = 0;
    const bridge = {
      createStartUpPageContainer: async () => result,
      rebuildPageContainer: async () => { rebuilds += 1; return true; },
      textContainerUpgrade: async () => true,
    } as unknown as LensBridge;
    await assert.rejects(new NativeLensView(bridge).initialize(), new RegExp(label));
    assert.equal(rebuilds, 0, `startup result ${result} is not a stale page`);
  }
});

test("microphone stop waits for an in-flight open before sending off", async () => {
  const controls: boolean[] = [];
  let releaseOpen: (() => void) | undefined;
  const opening = new Promise<void>((resolve) => { releaseOpen = resolve; });
  const microphone = new MicrophoneService({
    audioControl: async (enabled) => {
      controls.push(enabled);
      if (enabled) await opening;
      return true;
    },
  } satisfies AudioBridge);
  const started = microphone.start();
  await Promise.resolve(); // Let the queued hardware open begin.
  const stopped = microphone.stop();
  assert.equal(microphone.wanted, false);
  releaseOpen?.();
  assert.equal(await started, false);
  await stopped;
  assert.deepEqual(controls, [true, false]);
  assert.equal(microphone.wanted, false);
});

test("a new mic session after sleep opens only after the previous off completes", async () => {
  const controls: boolean[] = [];
  const microphone = new MicrophoneService({
    audioControl: async (enabled) => { controls.push(enabled); return true; },
  } satisfies AudioBridge);
  await microphone.stop();
  assert.equal(await microphone.start(), true);
  assert.equal(await microphone.start(), true);
  await microphone.stop();
  assert.equal(await microphone.start(), true);
  assert.deepEqual(controls, [false, true, false, true]);
});

test("a refused mic-off after an open retries once and reports persistent failure", async () => {
  const controls: boolean[] = [];
  let allowClose = false;
  const microphone = new MicrophoneService({
    audioControl: async (enabled) => {
      controls.push(enabled);
      return enabled || allowClose;
    },
  } satisfies AudioBridge);
  assert.equal(await microphone.start(), true);
  await assert.rejects(microphone.stop(), /may still be recording/);
  assert.deepEqual(controls, [true, false, false]);
  assert.equal(microphone.wanted, false);

  allowClose = true;
  assert.equal(await microphone.start(), true);
  await microphone.stop();
  assert.deepEqual(controls, [true, false, false, true, false]);
});

test("a transient mic-off refusal succeeds on its single retry", async () => {
  const controls: boolean[] = [];
  let closes = 0;
  const microphone = new MicrophoneService({
    audioControl: async (enabled) => {
      controls.push(enabled);
      if (enabled) return true;
      return ++closes >= 2;
    },
  } satisfies AudioBridge);
  assert.equal(await microphone.start(), true);
  await microphone.stop();
  assert.deepEqual(controls, [true, false, false]);
});
