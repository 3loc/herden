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

/**
 * Attention order, top first: a question waits on the user, a working Agent
 * waits on nothing, so working sinks to the bottom. Ties break by Host then
 * Space so rows never shuffle between snapshots.
 */
const STATUS_ORDER: Agent["status"][] = ["blocked", "failed", "done", "idle", "unknown", "working"];

export function attentionRank(status: Agent["status"]): number {
  const rank = STATUS_ORDER.indexOf(status);
  return rank === -1 ? STATUS_ORDER.length : rank;
}

export function byAttention(left: Agent, right: Agent): number {
  return attentionRank(left.status) - attentionRank(right.status)
    || (left.hostName ?? "").localeCompare(right.hostName ?? "")
    || (left.space || "").localeCompare(right.space || "");
}

/**
 * The spoken handle for a row. It is the 1-based position in the list the
 * wearer can see, never a Host id: "open five" has to mean the fifth row.
 * Two columns keep every bracket aligned past row nine.
 */
export const POSITION_WIDTH = 2;

export function positionMark(position: number): string {
  return String(position).slice(-POSITION_WIDTH).padStart(POSITION_WIDTH, " ");
}

/** One dense Space row: cursor, number, status, harness, Host, message. */
export function renderSpaceCard(agent: Agent, selected = false, position = 1): string {
  const prefix = `${selected ? ">" : " "}${positionMark(position)}${STATUS_LETTERS[agent.status]}[${harnessMark(agent.kind)}][${agent.hostName || "host"}]:`;
  return `${prefix}${truncate(spaceMessage(agent), Math.max(1, COLS - prefix.length))}`;
}

/**
 * The lens is one dense list: 5[W][Cdx][3loc]:last message. `debug` is the
 * temporary gesture diagnostic and always occupies the final row.
 */
export function renderList(snapshot: Snapshot, selected: number, online: boolean, empty = "no agents", debug?: string, notice: string[] = []): string {
  const tail = debug ? [truncate(debug)] : [];
  const head = notice.map((line) => truncate(line));
  if (snapshot.agents.length === 0) return frame([...head, online ? empty : "Host offline", ...tail]);
  const visible = windowAround(snapshot.agents, selected, ROWS - (online ? 0 : 1) - tail.length - head.length);
  const rows = visible.items.map((agent, index) => renderSpaceCard(agent, visible.start + index === selected, visible.start + index + 1));
  return frame([...head, ...(online ? [] : ["Host offline"]), ...rows, ...tail]);
}

/** The selected Space's terminal text, using only the G2 navigation gestures. */
export function renderDetail(agent: Agent, output: string[], offset: number, online: boolean, position = 1, notice: string[] = []): string {
  const head = notice.map((line) => truncate(line));
  const rows = Math.max(1, OUTPUT_ROWS - head.length);
  const start = Math.max(0, Math.min(offset, Math.max(0, output.length - OUTPUT_ROWS)));
  const visible = output.slice(start, start + rows).map((line) => truncate(line));
  const range = output.length === 0 ? "reading output" : `${start + 1}-${start + visible.length}/${output.length}`;
  return frame([
    ...head,
    truncate(`${positionMark(position).trim()}[${harnessMark(agent.kind)}][${agent.hostName || "host"}]:${spaceMessage(agent)}`),
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

/**
 * Temporary hardware diagnostic for the click issue: the last Even Hub event,
 * as one lens row. `field` names the envelope field it arrived in, so a click
 * that never reaches `sysEvent`/`textEvent` is visible on the glasses.
 */
export type GestureDebug = {
  count: number;
  field: string;
  eventType?: number;
  error?: string;
  /** Microphone phase and last transcript: the only window into mic hardware. */
  mic?: string;
  transcript?: string;
  /**
   * The live IMU triple and computed pitch delta. The G2's IMU frame, units
   * and sign are undocumented, so this row is how the wake thresholds in
   * `attention.ts` get calibrated: read real numbers off the lens, resting
   * and with the head raised, and set the constants from them. It precedes
   * the transcript because the transcript is also shown in the notice row.
   */
  imu?: string;
};

export function renderGestureDebug(gesture: GestureDebug): string {
  const mic = [
    gesture.imu ? ` ${gesture.imu}` : "",
    gesture.mic ? ` mic=${gesture.mic}` : "",
    gesture.transcript ? ` "${gesture.transcript}"` : "",
  ].join("");
  if (gesture.error) return truncate(`ev#${gesture.count} ${gesture.field} err ${gesture.error}${mic}`);
  if (gesture.count === 0) return truncate(`ev#${gesture.count} none yet${mic}`);
  return truncate(`ev#${gesture.count} ${gesture.field} type=${gesture.eventType ?? "?"}${mic}`);
}

/** Brightness follows urgency: full for anything demanding a decision. */
export function brightnessFor(agents: Agent[]): number {
  return agents.some((a) => a.status === "blocked" || a.status === "failed") ? BRIGHT : DIM;
}
