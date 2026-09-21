#!/usr/bin/env node

import { parseArgs } from "node:util";
import { createGateway, loadGatewayConfig } from "./gateway.mjs";

const { values } = parseArgs({ options: {
  config: { type: "string" },
  host: { type: "string", default: "127.0.0.1" },
  port: { type: "string", default: "8793" },
  help: { type: "boolean", default: false },
} });

if (values.help || !values.config) {
  console.log("usage: herden-glasses-gateway --config <path> [--host 127.0.0.1] [--port 8793]");
  process.exit(values.help ? 0 : 2);
}

const config = loadGatewayConfig(values.config);
const server = createGateway(config);
server.listen(Number(values.port), values.host, () => {
  console.log(`Herden glasses gateway listening on http://${values.host}:${values.port}`);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
