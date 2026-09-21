import assert from "node:assert/strict";
import http from "node:http";
import { once } from "node:events";
import { test } from "node:test";
import { createGateway } from "../src/gateway.mjs";

async function listen(server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return `http://127.0.0.1:${server.address().port}`;
}

test("gateway requires Tailscale identity", async (context) => {
  const gateway = createGateway({ hosts: [], stt: { path: "/stt", target: "http://127.0.0.1:1" } });
  context.after(() => gateway.close());
  const base = await listen(gateway);
  const response = await fetch(`${base}/health`);
  assert.equal(response.status, 401);
});

test("gateway routes Hosts with server-side credentials and strips the client token", async (context) => {
  let received;
  const upstream = http.createServer((req, res) => {
    received = { url: req.url, authorization: req.headers.authorization };
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.end('data: {"type":"snapshot"}\n\n');
  });
  context.after(() => upstream.close());
  const upstreamBase = await listen(upstream);
  const gateway = createGateway({
    hosts: [{ id: "one", name: "One", path: "/hosts/one", target: upstreamBase, token: "real-secret" }],
    stt: { path: "/stt", target: upstreamBase },
  });
  context.after(() => gateway.close());
  const base = await listen(gateway);
  const response = await fetch(`${base}/hosts/one/events?token=packaged-placeholder`, {
    headers: { "tailscale-user-login": "user@example.com" },
  });
  assert.equal(response.status, 200);
  assert.equal(await response.text(), 'data: {"type":"snapshot"}\n\n');
  assert.deepEqual(received, { url: "/events", authorization: "Bearer real-secret" });
  assert.equal(response.headers.get("access-control-allow-origin"), "*");
});

test("gateway streams transcription uploads to the configured service", async (context) => {
  let received;
  const upstream = http.createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    received = { url: req.url, contentType: req.headers["content-type"], body: Buffer.concat(chunks).toString() };
    res.writeHead(200, { "content-type": "application/json" });
    res.end('{"text":"open two"}');
  });
  context.after(() => upstream.close());
  const upstreamBase = await listen(upstream);
  const gateway = createGateway({ hosts: [], stt: { path: "/stt", target: upstreamBase } });
  context.after(() => gateway.close());
  const base = await listen(gateway);
  const response = await fetch(`${base}/stt/v1/transcribe`, {
    method: "POST",
    headers: { "content-type": "audio/wav", "tailscale-user-login": "user@example.com" },
    body: "wav-bytes",
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { text: "open two" });
  assert.deepEqual(received, { url: "/v1/transcribe", contentType: "audio/wav", body: "wav-bytes" });
});

test("closing an event stream does not crash the gateway", async (context) => {
  const upstream = http.createServer((_req, res) => {
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.write('data: {"type":"snapshot"}\n\n');
  });
  context.after(() => upstream.close());
  const upstreamBase = await listen(upstream);
  const gateway = createGateway({
    hosts: [{ id: "one", name: "One", path: "/hosts/one", target: upstreamBase, token: "secret" }],
    stt: { path: "/stt", target: upstreamBase },
  }, { allowInsecure: true });
  context.after(() => gateway.close());
  const base = await listen(gateway);

  await new Promise((resolve, reject) => {
    const request = http.get(`${base}/hosts/one/events`, (response) => {
      response.once("data", () => {
        response.destroy();
        resolve();
      });
    });
    request.once("error", reject);
  });

  const response = await fetch(`${base}/health`);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).ready, true);
});
