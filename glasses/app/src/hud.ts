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

/**
 * Herden's harness marks, as the Console uses them: the kind, never the model.
 * A pane with no interactive Agent is the user's shell.
 */
const HARNESS_MARKS: Record<string, string> = {
  codex: "Cdx", claude: "C", pi: "Pi",
  zsh: "Zsh", bash: "Bash", fish: "Fish",
  agent: "Zsh", shell: "Zsh", terminal: "Zsh", "": "Zsh",
};

/** Unknown kinds keep the column narrow rather than pretending to know them. */
export function harnessMark(kind?: string): string {
  const key = (kind ?? "").trim().toLowerCase();
  const known = HARNESS_MARKS[key];
  if (known) return known;
  return key.slice(0, 1).toUpperCase() + key.slice(1, 3);
}

/**
 * The Host has no last-message field; `agent.name` carries the terminal title,
 * which is the closest thing to one. Fall back to the Space when it adds
 * nothing.
 */
export function spaceMessage(agent: Agent): string {
  const space = agent.space || "Unnamed Space";
  const name = (agent.name ?? "").trim();
  return name && name !== space ? name : space;
}

/**
 * One three-character status bracket per row, so no column ever jumps.
 * `[Q]` is a question: the Agent is waiting on the wearer.
 */
const STATUS_LETTERS: Record<Agent["status"], string> = {
  working: "[W]", idle: "[I]", blocked: "[Q]", failed: "[F]", done: "[D]", unknown: "[?]",
};

/** One dense Space row: cursor, status, harness, Host, message. */
export function renderSpaceCard(agent: Agent, selected = false): string {
  const prefix = `${selected ? ">" : " "}${STATUS_LETTERS[agent.status]}[${harnessMark(agent.kind)}][${agent.hostName || "host"}]:`;
  return `${prefix}${truncate(spaceMessage(agent), Math.max(1, COLS - prefix.length))}`;
}

/** The lens is one dense list: [W][Cdx][3loc]:last message. */
export function renderList(snapshot: Snapshot, selected: number, online: boolean, empty = "no agents"): string {
  if (snapshot.agents.length === 0) return frame([online ? empty : "Host offline"]);
  const visible = windowAround(snapshot.agents, selected, online ? ROWS : ROWS - 1);
  const rows = visible.items.map((agent, index) => renderSpaceCard(agent, visible.start + index === selected));
  return frame(online ? rows : ["Host offline", ...rows]);
}

/** The selected Space's terminal text, using only the G2 navigation gestures. */
export function renderDetail(agent: Agent, output: string[], offset: number, online: boolean): string {
  const start = Math.max(0, Math.min(offset, Math.max(0, output.length - OUTPUT_ROWS)));
  const visible = output.slice(start, start + OUTPUT_ROWS).map((line) => truncate(line));
  const range = output.length === 0 ? "reading output" : `${start + 1}-${start + visible.length}/${output.length}`;
  return frame([
    truncate(`[${harnessMark(agent.kind)}][${agent.hostName || "host"}]:${spaceMessage(agent)}`),
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
