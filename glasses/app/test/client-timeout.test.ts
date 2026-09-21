import assert from "node:assert/strict";
import { test } from "node:test";
import { BridgeClient } from "../src/client.ts";

const command = { action: "send_text", agentId: "w1:pT", text: "hello", submit: false } as const;

test("a hung Host output read releases voice navigation after its deadline", async () => {
  const original = globalThis.fetch;
  let aborted = false;
  globalThis.fetch = ((_input: string | URL | Request, init?: RequestInit) => {
    init?.signal?.addEventListener("abort", () => { aborted = true; });
    return new Promise<Response>(() => {});
  }) as typeof fetch;
  try {
    const client = new BridgeClient({ baseUrl: "/hud", token: "test", onSnapshot: () => {}, requestTimeoutMs: 20 });
    await assert.rejects(client.readOutput("w1:pT"), /Host output timed out/);
    assert.equal(aborted, true);
  } finally { globalThis.fetch = original; }
});

test("a Host response with hung JSON parsing also obeys the deadline", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (async () => ({
    ok: true,
    json: () => new Promise<unknown>(() => {}),
  })) as typeof fetch;
  try {
    const client = new BridgeClient({ baseUrl: "/hud", token: "test", onSnapshot: () => {}, requestTimeoutMs: 20 });
    await assert.rejects(client.readOutput("w1:pT"), /Host output timed out/);
  } finally { globalThis.fetch = original; }
});

test("a timed-out Host command is never automatically resent", async () => {
  const original = globalThis.fetch;
  const errors: string[] = [];
  let requests = 0;
  globalThis.fetch = (() => {
    requests += 1;
    return new Promise<Response>(() => {});
  }) as typeof fetch;
  try {
    const client = new BridgeClient({
      baseUrl: "/hud", token: "test", onSnapshot: () => {}, requestTimeoutMs: 20,
      onCommandError: (message) => errors.push(message),
    });
    assert.equal(await client.send(command), false);
    assert.equal(requests, 1);
    assert.deepEqual(errors, ["Delivery is uncertain. Do not automatically retry."]);
  } finally { globalThis.fetch = original; }
});
