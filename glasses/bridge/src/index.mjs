#!/usr/bin/env node
/**
 * herden-glasses-bridge — Host-side half of the G2 HUD.
 *
 * Reads the Herden Host's local API socket and serves it to an Even Hub plugin
 * as Server-Sent Events, taking commands back over POST. SSE rather than
 * WebSocket because `EventSource` reconnects on its own, which is the whole
 * problem on a four-hour walk through patchy cell coverage — and because it
 * needs no dependencies.
 *
 * Bind this to a Tailscale interface, never to a public one. Nothing here
 * belongs on the open internet: the Host's own transport is SSH for a reason.
 */

import http from "node:http";
import { parseArgs } from "node:util";
import { call, defaultSocketPath, ping } from "./herden.mjs";
import { AgentWatcher } from "./watcher.mjs";

const { values: opts } = parseArgs({
  options: {
    port: { type: "string", default: "8791" },
    host: { type: "string", default: "127.0.0.1" },
    socket: { type: "string" },
    session: { type: "string" },
    token: { type: "string" },
    origin: { type: "string", default: "*" },
    "read-only": { type: "boolean", default: false },
    "poll-ms": { type: "string", default: "15000" },
    help: { type: "boolean", default: false },
  },
});

if (opts.help) {
  console.log(`herden-glasses-bridge

  --host <addr>     bind address (default 127.0.0.1; use your tailnet address)
  --port <n>        bind port (default 8791)
  --socket <path>   Herden API socket (default ~/.config/herden/herden.sock)
  --session <name>  named session, instead of --socket
  --token <str>     shared secret; required unless HERDEN_GLASSES_TOKEN is set
  --origin <str>    Access-Control-Allow-Origin value (default *)
  --read-only       serve status but refuse every command (safe against a live Host)
  --poll-ms <n>     safety-net poll interval (default 15000)
`);
  process.exit(0);
}

const socketPath = opts.socket ?? defaultSocketPath(opts.session);
const token = opts.token ?? process.env.HERDEN_GLASSES_TOKEN;
if (!token) {
  console.error("refusing to start without a token: pass --token or set HERDEN_GLASSES_TOKEN");
  process.exit(2);
}

const watcher = new AgentWatcher({ socketPath, pollMs: Number(opts["poll-ms"]) });
watcher.on("warn", (err) => console.warn("[watch]", err.message));
watcher.on("connected", () => console.log("[watch] subscribed"));

/** Connected SSE clients. */
const clients = new Set();

function broadcast(payload) {
  const frame = `data: ${JSON.stringify(payload)}\n\n`;
  for (const res of clients) res.write(frame);
}

watcher.on("snapshot", broadcast);

const cors = {
  "Access-Control-Allow-Origin": opts.origin,
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function authorised(req, url) {
  // EventSource cannot set headers, so the stream authenticates by query
  // parameter. POST prefers the Authorization header.
  const bearer = (req.headers.authorization ?? "").replace(/^Bearer\s+/i, "");
  const supplied = bearer || url.searchParams.get("token") || "";
  return supplied.length === token.length && timingSafeEqual(supplied, token);
}

/** Constant-time compare; avoids leaking the token a character at a time. */
function timingSafeEqual(a, b) {
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function send(res, status, body) {
  const json = JSON.stringify(body);
  res.writeHead(status, { ...cors, "content-type": "application/json" });
  res.end(json);
}

/**
 * Map a HUD action to `pane.send_input`.
 *
 * Everything routes through that one verified RPC rather than `agent.prompt`:
 * `{text, keys:["enter"]}` is an atomic type-and-submit, and key names are
 * accepted case-insensitively as `enter` / `esc` / `ctrl+c`.
 */
function commandToRpc({ action, agentId, text, key }) {
  if (!agentId) throw new Error("agentId is required");
  const params = { pane_id: agentId };
  switch (action) {
    case "approve":
      return { ...params, keys: ["enter"] };
    case "deny":
      return { ...params, keys: ["esc"] };
    case "interrupt":
      return { ...params, keys: ["ctrl+c"] };
    case "choose":
      if (!/^[0-9]$/.test(String(text ?? ""))) throw new Error("choose needs a single digit");
      return { ...params, text: String(text), keys: ["enter"] };
    case "prompt":
      if (!text) throw new Error("prompt needs text");
      return { ...params, text, keys: ["enter"] };
    case "key":
      if (!key) throw new Error("key is required");
      return { ...params, keys: [key] };
    default:
      throw new Error(`unknown action: ${action}`);
  }
}

async function readJson(req, limit = 64 * 1024) {
  let body = "";
  for await (const chunk of req) {
    body += chunk;
    if (body.length > limit) throw new Error("body too large");
  }
  return body ? JSON.parse(body) : {};
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === "OPTIONS") {
    res.writeHead(204, cors);
    return res.end();
  }

  if (url.pathname === "/health") {
    return send(res, 200, { ok: true, agents: watcher.snapshot?.agents.length ?? 0 });
  }

  if (!authorised(req, url)) return send(res, 401, { error: "unauthorised" });

  if (req.method === "GET" && url.pathname === "/events") {
    res.writeHead(200, {
      ...cors,
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive",
      "x-accel-buffering": "no",
    });
    // Tell EventSource to come back quickly after a cellular dropout.
    res.write("retry: 2000\n\n");
    if (watcher.snapshot) res.write(`data: ${JSON.stringify(watcher.snapshot)}\n\n`);
    clients.add(res);

    // Comment frames keep intermediaries from reaping an idle stream.
    const keepAlive = setInterval(() => res.write(": ping\n\n"), 20_000);
    keepAlive.unref?.();
    req.on("close", () => {
      clearInterval(keepAlive);
      clients.delete(res);
    });
    return;
  }

  if (req.method === "POST" && url.pathname === "/command") {
    if (opts["read-only"]) return send(res, 403, { error: "bridge is read-only" });
    try {
      const command = await readJson(req);
      const params = commandToRpc(command);
      const result = await call(socketPath, "pane.send_input", params);
      return send(res, 200, { ok: true, result });
    } catch (err) {
      return send(res, 400, { error: err.message });
    }
  }

  return send(res, 404, { error: "not found" });
});

// A path over the sun_path limit fails as a bare `connect EINVAL`, which reads
// like a bug in the client rather than a too-long path.
if (Buffer.byteLength(socketPath) > 107) {
  console.error(`socket path is ${Buffer.byteLength(socketPath)} bytes; the limit is 107`);
  console.error(`  ${socketPath}`);
  console.error("run from its directory and pass a relative path instead.");
  process.exit(2);
}

const port = Number(opts.port);
try {
  const info = await ping(socketPath);
  console.log(`[host] ${socketPath} — herden ${info?.version} protocol ${info?.protocol}`);
} catch (err) {
  console.error(`[host] cannot reach ${socketPath}: ${err.message}`);
  console.error("       is the Herden Host running? there is no auto-start on the socket path.");
  process.exit(1);
}

await watcher.start();
server.listen(port, opts.host, () => {
  console.log(
    `[http] http://${opts.host}:${port}  (SSE /events, POST /command)` +
      (opts["read-only"] ? "  [read-only: commands refused]" : ""),
  );
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    watcher.stop();
    server.close(() => process.exit(0));
  });
}
