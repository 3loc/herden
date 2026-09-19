import assert from "node:assert/strict";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { after, test } from "node:test";
import { HerdenError, call, defaultSocketPath, subscribe } from "../src/herden.mjs";

/**
 * A stand-in for the Host API socket that reproduces the documented behaviour:
 * one request per connection, one response line, then close — except
 * `events.subscribe`, which stays open and pushes `{event, data}` lines.
 */
function fakeHost(handler) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "herden-hud-"));
  const socketPath = path.join(dir, "herden.sock");
  const server = net.createServer((sock) => {
    sock.setEncoding("utf8");
    sock.once("data", (line) => handler(JSON.parse(line), sock));
  });
  server.listen(socketPath);
  const close = () =>
    new Promise((resolve) => server.close(() => fs.rmSync(dir, { recursive: true, force: true }) ?? resolve()));
  return { socketPath, close, server };
}

const cleanups = [];
after(async () => {
  for (const fn of cleanups) await fn();
});

test("default socket paths follow the documented layout", () => {
  assert.equal(defaultSocketPath(), path.join(os.homedir(), ".config/herden/herden.sock"));
  assert.equal(
    defaultSocketPath("work"),
    path.join(os.homedir(), ".config/herden/sessions/work/herden.sock"),
  );
});

test("a call sends id/method/params and resolves the result", async () => {
  let received;
  const host = fakeHost((req, sock) => {
    received = req;
    sock.end(JSON.stringify({ id: req.id, result: { version: "0.8.2", protocol: 20 } }) + "\n");
  });
  cleanups.push(host.close);

  const result = await call(host.socketPath, "ping");
  assert.equal(result.protocol, 20);
  assert.equal(received.method, "ping");
  assert.deepEqual(received.params, {}, "params is required; {} satisfies it");
  assert.equal(typeof received.id, "string");
});

test("an error response rejects with its code", async () => {
  const host = fakeHost((req, sock) => {
    sock.end(JSON.stringify({ id: req.id, error: { code: "pane_not_found", message: "gone" } }) + "\n");
  });
  cleanups.push(host.close);

  await assert.rejects(
    () => call(host.socketPath, "pane.send_input", { pane_id: "w9:pZ" }),
    (err) => err instanceof HerdenError && err.code === "pane_not_found",
  );
});

test("a response carrying the wrong id is still matched", async () => {
  // Malformed requests are answered with `id: ""`. One request owns its
  // connection, so the first line is ours regardless of what id comes back.
  const host = fakeHost((_req, sock) => {
    sock.end(JSON.stringify({ id: "", result: { ok: true } }) + "\n");
  });
  cleanups.push(host.close);

  assert.deepEqual(await call(host.socketPath, "whatever"), { ok: true });
});

test("a connection closed without a response rejects rather than hanging", async () => {
  const host = fakeHost((_req, sock) => sock.end());
  cleanups.push(host.close);

  await assert.rejects(() => call(host.socketPath, "ping"), /closed without a response/);
});

test("a silent server times out", async () => {
  const host = fakeHost(() => {});
  cleanups.push(host.close);

  await assert.rejects(() => call(host.socketPath, "ping", {}, { timeoutMs: 80 }), /timed out/);
});

test("unparseable lines are skipped rather than throwing", async () => {
  const host = fakeHost((req, sock) => {
    sock.write("this is not json\n");
    sock.end(JSON.stringify({ id: req.id, result: "recovered" }) + "\n");
  });
  cleanups.push(host.close);

  assert.equal(await call(host.socketPath, "ping"), "recovered");
});

test("subscribe passes pane-scoped entries through and streams events", async () => {
  let request;
  const host = fakeHost((req, sock) => {
    request = req;
    sock.write(JSON.stringify({ id: req.id, result: { ok: true } }) + "\n");
    sock.write(JSON.stringify({ event: "pane.agent_status_changed", data: { pane_id: "w1:pT" } }) + "\n");
  });
  cleanups.push(host.close);

  const events = [];
  const session = subscribe(
    host.socketPath,
    [{ type: "pane.agent_status_changed", pane_id: "w1:pT" }],
    { onEvent: (e) => events.push(e) },
  );

  await new Promise((r) => setTimeout(r, 120));
  session.close();

  assert.equal(request.method, "events.subscribe");
  assert.deepEqual(request.params.subscriptions, [
    { type: "pane.agent_status_changed", pane_id: "w1:pT" },
  ]);
  assert.equal(events.length, 1);
  assert.equal(events[0].event, "pane.agent_status_changed");
});

test("a failed subscription surfaces as an error, not silence", async () => {
  const host = fakeHost((req, sock) => {
    // events.subscribe is all-or-nothing; one dead pane fails the request.
    sock.write(
      JSON.stringify({ id: `${req.id}:sub:0:probe`, error: { code: "pane_not_found", message: "gone" } }) + "\n",
    );
  });
  cleanups.push(host.close);

  const errors = [];
  const session = subscribe(host.socketPath, [{ type: "pane.agent_status_changed", pane_id: "dead" }], {
    onEvent: () => {},
    onError: (err) => errors.push(err),
  });

  await new Promise((r) => setTimeout(r, 120));
  session.close();

  assert.equal(errors.length, 1);
  assert.equal(errors[0].code, "pane_not_found");
});
