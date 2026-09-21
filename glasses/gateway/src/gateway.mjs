import http from "node:http";
import { readFileSync } from "node:fs";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type",
  "access-control-allow-methods": "GET, POST, OPTIONS",
};

function json(res, status, payload) {
  res.writeHead(status, { ...CORS, "content-type": "application/json" });
  res.end(JSON.stringify(payload));
}

function authenticated(req, allowInsecure) {
  return allowInsecure || Boolean(req.headers["tailscale-user-login"]);
}

function routeFor(pathname, config) {
  const hosts = [...config.hosts].sort((a, b) => b.path.length - a.path.length);
  for (const host of hosts) {
    if (pathname === host.path || pathname.startsWith(`${host.path}/`)) {
      return { kind: "host", route: host, suffix: pathname.slice(host.path.length) || "/" };
    }
  }
  if (pathname === config.stt.path || pathname.startsWith(`${config.stt.path}/`)) {
    return { kind: "stt", route: config.stt, suffix: pathname.slice(config.stt.path.length) || "/" };
  }
  return null;
}

function upstreamHeaders(req, route) {
  const headers = new Headers();
  for (const name of ["accept", "content-type", "content-length"]) {
    const value = req.headers[name];
    if (typeof value === "string") headers.set(name, value);
  }
  if (route.token) headers.set("authorization", `Bearer ${route.token}`);
  return headers;
}

async function proxy(req, res, match, fetchImpl) {
  const incoming = new URL(req.url, "http://gateway.invalid");
  incoming.searchParams.delete("token");
  const target = new URL(match.suffix + incoming.search, `${match.route.target.replace(/\/$/, "")}/`);
  const controller = new AbortController();
  req.on("aborted", () => controller.abort());
  res.on("close", () => {
    if (!res.writableEnded) controller.abort();
  });
  const hasBody = req.method !== "GET" && req.method !== "HEAD";
  const options = {
    method: req.method,
    headers: upstreamHeaders(req, match.route),
    signal: controller.signal,
    redirect: "manual",
    ...(hasBody ? { body: req, duplex: "half" } : {}),
  };
  const upstream = await fetchImpl(target, options);
  const headers = { ...CORS };
  for (const name of ["content-type", "cache-control", "x-accel-buffering"]) {
    const value = upstream.headers.get(name);
    if (value) headers[name] = value;
  }
  res.writeHead(upstream.status, headers);
  if (!upstream.body) return res.end();
  try {
    await pipeline(Readable.fromWeb(upstream.body), res);
  } catch (error) {
    // Closing an EventSource aborts its infinite upstream response. That is a
    // normal client lifecycle event, not a gateway failure.
    if (controller.signal.aborted || res.destroyed) return;
    throw error;
  }
}

export function createGateway(config, options = {}) {
  const allowInsecure = options.allowInsecure === true;
  const fetchImpl = options.fetchImpl ?? fetch;
  return http.createServer(async (req, res) => {
    if (req.method === "OPTIONS") {
      res.writeHead(204, CORS);
      return res.end();
    }
    if (!authenticated(req, allowInsecure)) return json(res, 401, { error: "Tailscale identity required" });
    const url = new URL(req.url, "http://gateway.invalid");
    if (url.pathname === "/health") {
      return json(res, 200, { ready: true, hosts: config.hosts.map(({ id, name, path }) => ({ id, name, path })) });
    }
    const match = routeFor(url.pathname, config);
    if (!match) return json(res, 404, { error: "not found" });
    try {
      await proxy(req, res, match, fetchImpl);
    } catch (error) {
      if (!res.headersSent) json(res, 502, { error: error instanceof Error ? error.message : "upstream failed" });
      else res.destroy(error instanceof Error ? error : undefined);
    }
  });
}

export function loadGatewayConfig(path) {
  const config = JSON.parse(readFileSync(path, "utf8"));
  if (!Array.isArray(config.hosts) || config.hosts.length === 0 || !config.stt?.target) {
    throw new Error("gateway config requires hosts and stt.target");
  }
  const paths = new Set();
  for (const host of config.hosts) {
    if (!host.id || !host.name || !host.path?.startsWith("/hosts/") || !host.target || !host.token_file) {
      throw new Error("each gateway Host requires id, name, /hosts/ path, target and token_file");
    }
    if (paths.has(host.path)) throw new Error(`duplicate Host path: ${host.path}`);
    paths.add(host.path);
    host.token = readFileSync(host.token_file, "utf8").trim();
    if (!host.token) throw new Error(`empty token file: ${host.token_file}`);
  }
  config.stt.path ??= "/stt";
  return config;
}
