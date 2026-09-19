#!/usr/bin/env node
/**
 * A fake Herden Host API socket, so the HUD can be developed without one.
 *
 * Reproduces the behaviours that actually shape the client: one request per
 * connection, `events.subscribe` held open, pane-scoped subscriptions failing
 * all-or-nothing when they name a dead pane, and agents that drift between
 * statuses on their own so the wake policy has something to react to.
 *
 *   node dev/mock-host.mjs /tmp/mock-herden.sock
 *   node src/index.mjs --socket /tmp/mock-herden.sock --token dev
 */

import fs from "node:fs";
import net from "node:net";

const socketPath = process.argv[2] ?? "/tmp/mock-herden.sock";
fs.rmSync(socketPath, { force: true });

const agents = [
  { pane_id: "w1:pT", name: "auth-refactor", label: "herden", status: "working" },
  { pane_id: "w1C:p1", name: "landing-copy", label: "landing", status: "idle" },
  { pane_id: "wR:pC", name: "host-release", label: "runtime", status: "blocked" },
  { pane_id: "wV:p1H", name: "relay-tests", label: "relay", status: "done" },
];

const ROTATION = ["working", "blocked", "working", "done", "idle"];
const listeners = new Set();

// Drift one agent every few seconds so wake transitions actually fire.
setInterval(() => {
  const agent = agents[Math.floor(Math.random() * agents.length)];
  const next = ROTATION[Math.floor(Math.random() * ROTATION.length)];
  if (agent.status === next) return;
  agent.status = next;
  console.log(`[mock] ${agent.name} -> ${next}`);
  for (const sock of listeners) {
    sock.write(
      JSON.stringify({
        event: "pane.agent_status_changed",
        data: { pane_id: agent.pane_id, status: next },
      }) + "\n",
    );
  }
}, 4000);

const known = new Set(agents.map((a) => a.pane_id));

function handle(request, sock) {
  const reply = (body) => sock.end(JSON.stringify({ id: request.id, ...body }) + "\n");

  switch (request.method) {
    case "ping":
      return reply({ result: { version: "0.8.2", protocol: 20, capabilities: ["live_handoff"] } });

    case "agent.list":
      return reply({ result: { agents } });

    case "pane.send_input": {
      const { pane_id, text, keys } = request.params ?? {};
      if (!known.has(pane_id)) {
        return reply({ error: { code: "pane_not_found", message: `no pane ${pane_id}` } });
      }
      console.log(`[mock] send_input ${pane_id} text=${JSON.stringify(text ?? "")} keys=${keys ?? []}`);
      const agent = agents.find((a) => a.pane_id === pane_id);
      if (keys?.includes("ctrl+c")) agent.status = "idle";
      else if (agent.status === "blocked") agent.status = "working";
      return reply({ result: { ok: true } });
    }

    case "events.subscribe": {
      const subscriptions = request.params?.subscriptions ?? [];
      // Protocol 22 discriminates on `type`; a `kind` key is rejected outright.
      const untyped = subscriptions.findIndex((s) => !s.type);
      if (untyped !== -1) {
        return reply({
          error: { code: "invalid_request", message: "invalid request: missing field `type`" },
        });
      }
      const dead = subscriptions.findIndex((s) => s.pane_id && !known.has(s.pane_id));
      if (dead !== -1) {
        // All-or-nothing: one dead pane fails the whole request, and the error
        // id does not correlate with the request id.
        return reply({
          id: `${request.id}:sub:${dead}:probe`,
          error: { code: "pane_not_found", message: "pane has exited" },
        });
      }
      sock.write(JSON.stringify({ id: request.id, result: { ok: true } }) + "\n");
      listeners.add(sock);
      sock.on("close", () => listeners.delete(sock));
      return; // Held open: the one method that does not close.
    }

    default:
      return reply({ error: { code: "unknown_method", message: request.method } });
  }
}

net
  .createServer((sock) => {
    sock.setEncoding("utf8");
    sock.once("data", (line) => {
      let request;
      try {
        request = JSON.parse(line);
      } catch {
        // Malformed requests are answered with an empty id, not the sender's.
        return sock.end(JSON.stringify({ id: "", error: { code: "bad_request", message: "unparseable" } }) + "\n");
      }
      handle(request, sock);
    });
  })
  .listen(socketPath, () => console.log(`[mock] herden socket at ${socketPath}`));

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    fs.rmSync(socketPath, { force: true });
    process.exit(0);
  });
}
