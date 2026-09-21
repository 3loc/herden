import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

test("private manifest requires one explicit HTTPS origin", async () => {
  const missing = spawnSync(process.execPath, ["dev/private-manifest.mjs"], { encoding: "utf8" });
  assert.equal(missing.status, 2);
  assert.match(missing.stderr, /explicit https/);

  const invalid = spawnSync(process.execPath, ["dev/private-manifest.mjs"], {
    encoding: "utf8", env: { ...process.env, HERDEN_HUD_ALLOWED_ORIGIN: "http://host.local" },
  });
  assert.equal(invalid.status, 2);

  const directory = await mkdtemp(join(tmpdir(), "herden-even-manifest-"));
  const source = join(directory, "app.json");
  const output = join(directory, "private.json");
  await writeFile(source, JSON.stringify({
    permissions: [
      { name: "network", desc: "network", whitelist: [] },
      { name: "g2-microphone", desc: "voice" },
    ],
  }));
  const valid = spawnSync(process.execPath, ["dev/private-manifest.mjs"], {
    encoding: "utf8",
    env: {
      ...process.env,
      HERDEN_HUD_ALLOWED_ORIGIN: "https://gateway.example.ts.net/",
      HERDEN_HUD_MANIFEST_SOURCE: source,
      HERDEN_HUD_MANIFEST_OUTPUT: output,
    },
  });
  assert.equal(valid.status, 0, valid.stderr);
  const manifest = JSON.parse(await readFile(output, "utf8"));
  assert.deepEqual(manifest.permissions[0].whitelist, ["https://gateway.example.ts.net"]);
  assert.equal(manifest.permissions[1].name, "g2-microphone");
});
