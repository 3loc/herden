import { test } from "node:test";
import assert from "node:assert/strict";

import { createHttpServer } from "../src/server.js";

test("standalone server exposes health without secrets", async (t) => {
  const server = createHttpServer({});
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  t.after(() => new Promise((resolve) => server.close(resolve)));

  const address = server.address();
  assert.notEqual(address, null);
  assert.equal(typeof address, "object");
  const response = await fetch(`http://127.0.0.1:${address.port}/health`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ok" });
});

test("standalone server forwards POST requests to the relay", async (t) => {
  const server = createHttpServer({});
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  t.after(() => new Promise((resolve) => server.close(resolve)));

  const address = server.address();
  assert.notEqual(address, null);
  assert.equal(typeof address, "object");
  const response = await fetch(`http://127.0.0.1:${address.port}/push`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "{}",
  });
  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), { error: "relay_misconfigured" });
});
