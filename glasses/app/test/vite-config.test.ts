import assert from "node:assert/strict";
import { test } from "node:test";

test("development server forwards the relative STT route to the configured service", async () => {
  process.env.HERDEN_HUD_STT_TARGET = "http://127.0.0.1:8022";
  const { default: config } = await import("../vite.config.ts?stt-proxy-test");
  const proxies = config.server?.proxy as Record<string, { rewrite?: (path: string) => string }>;

  assert.ok(proxies["/stt"]);
  assert.equal(proxies["/stt"]?.rewrite?.("/stt/v1/transcribe"), "/v1/transcribe");
});
