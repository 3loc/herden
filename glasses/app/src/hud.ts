/**
 * Pure text rendering for the lens. No SDK imports, so it is testable in Node.
 *
 * The Even firmware exposes one fixed text face; it has no font-size API. Keep
 * lens copy deliberately short so that the fixed face reads as a quiet glance.
 */

import type { Agent, Snapshot } from "./protocol";
import { PIXEL_COLS, PIXEL_ROWS } from "./pixel-font.ts";

export const COLS = PIXEL_COLS;
/** The Tamzen terminal face fits twenty lens rows. */
export const ROWS = PIXEL_ROWS;
const OUTPUT_ROWS = ROWS - 3;

/** Text brightness is 0-4 in the SDK; the lens washes out in direct sun. */
export const BRIGHT = 4;
export const DIM = 2;

const MARKS: Record<Agent["status"], string> = {
  blocked: "!",
  failed: "x",
  done: "+",
  working: ">",
  idle: "-",
  unknown: "?",
};

export function truncate(text: string, width = COLS): string {
  return text.length <= width ? text : `${text.slice(0, Math.max(0, width - 1))}…`;
}

/** Empty transcript rows waste an entire G2 text container. */
export function compactOutputLines(text: string): string[] {
  const lines = text.split("\n").filter((line) => line.trim().length > 0);
  return lines.length > 0 ? lines : ["No readable output yet."];
}

function frame(lines: string[]): string {
  return lines.slice(0, ROWS).map((line) => truncate(line)).join("\n");
}

/** One dense Agent row. The cursor is deliberately the only list chrome. */
export function renderSpaceCard(agent: Agent, selected = false): string {
  const host = agent.hostName || "host";
  const kind = agent.kind || "agent";
  const state = agent.status;
  const cursor = selected ? ">" : " ";
  const prefix = `${cursor}${host}:${kind}:`;
  const suffix = `:${state}`;
  return `${prefix}${truncate(agent.space || "Unnamed Space", Math.max(1, COLS - prefix.length - suffix.length))}${suffix}`;
}

/** The lens is one dense list: host:agent:space:state. */
export function renderList(snapshot: Snapshot, selected: number, online: boolean): string {
  if (snapshot.agents.length === 0) return frame([online ? "no agents" : "Host offline"]);
  const visible = windowAround(snapshot.agents, selected, online ? ROWS : ROWS - 1);
  const rows = visible.items.map((agent, index) => renderSpaceCard(agent, visible.start + index === selected));
  return frame(online ? rows : ["Host offline", ...rows]);
}

/** The selected Space's terminal text, using only the G2 navigation gestures. */
export function renderDetail(agent: Agent, output: string[], offset: number, online: boolean): string {
  const host = agent.hostName || "host";
  const kind = agent.kind || "agent";
  const start = Math.max(0, Math.min(offset, Math.max(0, output.length - OUTPUT_ROWS)));
  const visible = output.slice(start, start + OUTPUT_ROWS).map((line) => truncate(line));
  const range = output.length === 0 ? "reading output" : `${start + 1}-${start + visible.length}/${output.length}`;
  return frame([
    truncate(`${host}:${kind}:${agent.space || "Unnamed Space"}`),
    ...visible,
    `${MARKS[agent.status]} ${agent.status}  ${range}${online ? "" : " offline"}`,
    "double tap: back",
  ]);
}

export function outputWindowSize(): number { return OUTPUT_ROWS; }

/** Keep the selected row on screen without scrolling past either end. */
export function windowAround<T>(
  items: T[],
  selected: number,
  size: number,
): { start: number; items: T[] } {
  if (items.length <= size) return { start: 0, items };
  const start = Math.max(0, Math.min(selected - Math.floor(size / 2), items.length - size));
  return { start, items: items.slice(start, start + size) };
}

/** Brightness follows urgency: full for anything demanding a decision. */
export function brightnessFor(agents: Agent[]): number {
  return agents.some((a) => a.status === "blocked" || a.status === "failed") ? BRIGHT : DIM;
}
