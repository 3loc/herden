import assert from "node:assert/strict";
import { test } from "node:test";
import { BridgeClient } from "../src/client.ts";

test("send_text can insert without Enter, while voice dictation requests atomic submit", async () => {
  const original = globalThis.fetch;
  let request: { url: string; init?: RequestInit } | undefined;
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    request = { url: String(input), init };
    return new Response(null, { status: 204 });
  }) as typeof fetch;

  try {
    const client = new BridgeClient({
      baseUrl: "http://host.test:8791/",
      token: "secret",
      onSnapshot: () => {},
    });
    const delivered = await client.send({
      action: "send_text", agentId: "w1:pT", text: "run the tests", submit: false,
    });

    assert.equal(delivered, true);
    assert.equal(request?.url, "http://host.test:8791/command");
    assert.equal(request?.init?.method, "POST");
    assert.deepEqual(request?.init?.headers, {
      "content-type": "application/json", authorization: "Bearer secret",
    });
    assert.deepEqual(JSON.parse(String(request?.init?.body)), {
      action: "send_text", agentId: "w1:pT", text: "run the tests", submit: false,
    });
    assert.equal(await client.send({ action: "send_text", agentId: "w1:pT", text: "say hello", submit: true }), true);
    assert.deepEqual(JSON.parse(String(request?.init?.body)), {
      action: "send_text", agentId: "w1:pT", text: "say hello", submit: true,
    });
  } finally {
    globalThis.fetch = original;
  }
});
