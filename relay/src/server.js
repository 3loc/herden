import http from "node:http";
import { pathToFileURL } from "node:url";

import { createRelay } from "./worker.js";

const MAX_REQUEST_BYTES = 8192;

async function readRequestBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_REQUEST_BYTES) return null;
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export function createHttpServer(env = process.env) {
  const relay = createRelay();
  return http.createServer(async (incoming, outgoing) => {
    try {
      const host = incoming.headers.host ?? "localhost";
      const url = new URL(incoming.url ?? "/", `http://${host}`);
      const headers = new Headers();
      for (const [name, value] of Object.entries(incoming.headers)) {
        if (Array.isArray(value)) {
          for (const item of value) headers.append(name, item);
        } else if (value !== undefined) {
          headers.set(name, value);
        }
      }

      const hasBody = incoming.method !== "GET" && incoming.method !== "HEAD";
      const body = hasBody ? await readRequestBody(incoming) : undefined;
      if (body === null) {
        outgoing.writeHead(413, { "content-type": "application/json" });
        outgoing.end('{"error":"request_too_large"}');
        return;
      }

      const request = new Request(url, {
        method: incoming.method,
        headers,
        body,
      });
      const response = await relay.fetch(request, env);
      const responseBody = Buffer.from(await response.arrayBuffer());
      outgoing.writeHead(response.status, Object.fromEntries(response.headers.entries()));
      outgoing.end(responseBody);
    } catch {
      if (!outgoing.headersSent) {
        outgoing.writeHead(500, { "content-type": "application/json" });
      }
      outgoing.end('{"error":"internal_error"}');
    }
  });
}

export function startServer(env = process.env) {
  const port = Number.parseInt(env.PORT ?? "8080", 10);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("PORT must be an integer from 1 through 65535");
  }
  const server = createHttpServer(env);
  server.listen(port, "0.0.0.0", () => {
    process.stdout.write(`Herden Push Relay listening on ${port}\n`);
  });
  process.on("SIGTERM", () => server.close());
  process.on("SIGINT", () => server.close());
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startServer();
}
