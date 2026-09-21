#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";

const origin = process.env.HERDEN_HUD_ALLOWED_ORIGIN?.replace(/\/$/, "");
if (!origin || !origin.startsWith("https://")) {
  console.error("HERDEN_HUD_ALLOWED_ORIGIN must be one explicit https:// origin");
  process.exit(2);
}

const source = process.env.HERDEN_HUD_MANIFEST_SOURCE ?? new URL("../app.json", import.meta.url);
const target = process.env.HERDEN_HUD_MANIFEST_OUTPUT ?? new URL("../dist/app.private.json", import.meta.url);
const manifest = JSON.parse(await readFile(source, "utf8"));
const network = manifest.permissions.find((permission) => permission.name === "network");
if (!network) throw new Error("app.json has no network permission");
network.whitelist = [origin];
await writeFile(target, `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600 });
console.log(`private manifest allows ${origin}`);
