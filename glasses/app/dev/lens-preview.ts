#!/usr/bin/env node
/**
 * Prints what the lens would show, using the same renderer the glasses run.
 *
 * The simulator is a desktop GUI and needs a display; this needs a terminal.
 * It exercises the real render policy against a real bridge, so wake
 * behaviour, ordering and the character budget can be judged without hardware.
 *
 *   node dev/lens-preview.ts --url http://127.0.0.1:8791 --token dev
 *
 * Keys: j/k move, l detail, h list, q quit.
 */

import { emitKeypressEvents } from "node:readline";
import { brightnessFor, COLS, renderDetail, renderList } from "../src/hud.ts";
import type { Agent, Snapshot } from "../src/protocol.ts";

const args = new Map<string, string>();
for (let i = 2; i < process.argv.length; i += 2) {
  args.set(process.argv[i]!.replace(/^--/, ""), process.argv[i + 1] ?? "");
}
const baseUrl = args.get("url") ?? "http://127.0.0.1:8791";
const token = args.get("token") ?? "dev";

const state = {
  view: "list" as "list" | "detail",
  selected: 0,
  online: false,
  snapshot: null as Snapshot | null,
};

const selectedAgent = (): Agent | null => state.snapshot?.agents[state.selected] ?? null;

/** Draw the frame inside a box the shape of the 576x288 canvas. */
function draw(): void {
  const snapshot = state.snapshot;
  const text = !snapshot
    ? "connecting to herden…"
    : state.view === "detail" && selectedAgent()
      ? renderDetail(selectedAgent()!, ["Open this Space in the glasses simulator."], 0, state.online)
      : renderList(snapshot, state.selected, state.online);

  const bright = brightnessFor(snapshot?.agents ?? []);
  const green = bright >= 4 ? "\x1b[92m" : "\x1b[32m";
  const rule = "─".repeat(COLS);

  process.stdout.write("\x1b[2J\x1b[H");
  console.log(`\x1b[90m┌${rule}┐\x1b[0m`);
  for (const line of text.split("\n")) {
    console.log(`\x1b[90m│\x1b[0m${green}${line.padEnd(COLS)}\x1b[0m\x1b[90m│\x1b[0m`);
  }
  console.log(`\x1b[90m└${rule}┘\x1b[0m`);
  console.log(
    `\x1b[90m  576x288 · brightness ${bright}/4 · ${state.online ? "live" : "offline"}\x1b[0m`,
  );
  console.log("\x1b[90m  j/k move  l detail  h list  q quit\x1b[0m");
}

/** Minimal SSE reader; `EventSource` is a browser global the plugin uses instead. */
async function stream(): Promise<void> {
  for (;;) {
    try {
      const response = await fetch(`${baseUrl}/events?token=${encodeURIComponent(token)}`);
      if (!response.ok || !response.body) throw new Error(`HTTP ${response.status}`);
      state.online = true;

      let buffer = "";
      for await (const chunk of response.body) {
        buffer += Buffer.from(chunk).toString("utf8");
        let split: number;
        while ((split = buffer.indexOf("\n\n")) !== -1) {
          const frame = buffer.slice(0, split);
          buffer = buffer.slice(split + 2);
          const data = frame
            .split("\n")
            .filter((l) => l.startsWith("data:"))
            .map((l) => l.slice(5).trim())
            .join("");
          if (!data) continue;
          const snapshot = JSON.parse(data) as Snapshot;
          const previousId = selectedAgent()?.id;
          state.snapshot = snapshot;
          const moved = snapshot.agents.findIndex((a) => a.id === previousId);
          state.selected = moved >= 0 ? moved : 0;
          if (snapshot.wake.length > 0) {
            const target = snapshot.agents.findIndex((a) => a.id === snapshot.wake[0]);
            if (target >= 0) {
              state.selected = target;
              state.view = "detail";
            }
          }
          draw();
        }
      }
    } catch {
      // Fall through to the retry below; the bridge may just be restarting.
    }
    state.online = false;
    draw();
    await new Promise((r) => setTimeout(r, 2000));
  }
}

emitKeypressEvents(process.stdin);
if (process.stdin.isTTY) process.stdin.setRawMode(true);
process.stdin.on("keypress", (_str, key) => {
  const count = state.snapshot?.agents.length ?? 0;
  switch (key.name) {
    case "q": process.exit(0); break;
    case "j": state.selected = Math.min(count - 1, state.selected + 1); break;
    case "k": state.selected = Math.max(0, state.selected - 1); break;
    case "l": state.view = "detail"; break;
    case "h": state.view = "list"; break;
    default: return;
  }
  draw();
});

draw();
void stream();
