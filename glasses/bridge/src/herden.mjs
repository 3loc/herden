/**
 * Minimal NDJSON client for the Herden Host API socket.
 *
 * The socket serves one request per connection: write one line, read one line,
 * close. Only `events.subscribe` keeps the connection open. Because a single
 * request owns its connection, the first response line is unambiguously ours —
 * so we never key responses by id, which also sidesteps the Host answering
 * malformed requests with `id: ""`.
 */

import net from "node:net";
import os from "node:os";
import path from "node:path";

/** Default socket for the unnamed session. */
export function defaultSocketPath(session) {
  const root = path.join(os.homedir(), ".config", "herden");
  return session
    ? path.join(root, "sessions", session, "herden.sock")
    : path.join(root, "herden.sock");
}

class HerdenError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`);
    this.name = "HerdenError";
    this.code = code;
  }
}

let seq = 0;
const nextId = () => `hud-${process.pid}-${++seq}`;

/**
 * Read newline-delimited JSON off a socket, invoking `onLine` per parsed value.
 * Returns a function to feed raw chunks in.
 */
function lineReader(onLine) {
  let buf = "";
  return (chunk) => {
    buf += chunk;
    let nl;
    while ((nl = buf.indexOf("\n")) !== -1) {
      const line = buf.slice(0, nl).trim();
      buf = buf.slice(nl + 1);
      if (!line) continue;
      let value;
      try {
        value = JSON.parse(line);
      } catch {
        continue; // Parse leniently: the API has no stability guarantee.
      }
      onLine(value);
    }
  };
}

/**
 * Issue one RPC and resolve with `result`.
 *
 * `params` is required by the wire format; `{}` satisfies it.
 */
export function call(socketPath, method, params = {}, { timeoutMs = 10_000 } = {}) {
  return new Promise((resolve, reject) => {
    const sock = net.createConnection(socketPath);
    let settled = false;

    const finish = (err, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      sock.destroy();
      err ? reject(err) : resolve(value);
    };

    const timer = setTimeout(
      () => finish(new Error(`${method} timed out after ${timeoutMs}ms`)),
      timeoutMs,
    );

    const feed = lineReader((msg) => {
      if (msg.error) finish(new HerdenError(msg.error.code, msg.error.message));
      else finish(null, msg.result);
    });

    sock.setEncoding("utf8");
    sock.on("data", feed);
    sock.on("error", finish);
    sock.on("close", () => finish(new Error(`${method}: socket closed without a response`)));
    sock.on("connect", () => {
      sock.write(JSON.stringify({ id: nextId(), method, params }) + "\n");
    });
  });
}

/**
 * Hold an `events.subscribe` connection open, invoking `onEvent({event, data})`
 * per pushed line. Returns a handle with `.close()`.
 *
 * `subscriptions` is passed through verbatim, so pane-scoped entries are
 * allowed — but `events.subscribe` is all-or-nothing, and a single entry naming
 * a pane that has since exited fails the entire request with `pane_not_found`.
 * Pane-scoped subscriptions are therefore snapshot-derived and must never
 * outlive the connection they were taken on; see `watch()` for the cycle that
 * enforces that.
 */
export function subscribe(socketPath, subscriptions, { onEvent, onError, onClose }) {
  const sock = net.createConnection(socketPath);
  const feed = lineReader((msg) => {
    if (msg.event) onEvent(msg);
    else if (msg.error) onError?.(new HerdenError(msg.error.code, msg.error.message));
  });

  sock.setEncoding("utf8");
  sock.on("data", feed);
  sock.on("error", (err) => onError?.(err));
  sock.on("close", () => onClose?.());
  sock.on("connect", () => {
    sock.write(
      JSON.stringify({ id: nextId(), method: "events.subscribe", params: { subscriptions } }) + "\n",
    );
  });

  return { close: () => sock.destroy() };
}

/** First call on any new connection path: returns the server protocol version. */
export const ping = (socketPath) => call(socketPath, "ping");

export { HerdenError };
