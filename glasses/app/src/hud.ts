/**
 * Pure text rendering for the lens. No SDK imports, so it is testable in Node.
 *
 * The G2 firmware owns the face, shaping and Unicode glyph set. It exposes no
 * font-size or line-height control, so use the complete 576x288 surface with
 * no padding and keep application chrome compact.
 */

import type { Agent, Snapshot } from "./protocol";
import { getTextWidth, pxTruncate } from "@evenrealities/pretext";

/** Ten firmware lines fit without turning the text container into a scroller. */
export const COLS = 48;
export const ROWS = 10;
/** Leave a little room for firmware/simulator glyph fallback differences. */
export const LENS_TEXT_WIDTH = 544;
// One identity row and one anchored footer leave eight rows for output.
const OUTPUT_ROWS = ROWS - 2;

/** Text brightness is 0-4 in the SDK; the lens washes out in direct sun. */
export const BRIGHT = 4;
export const DIM = 2;

export function truncate(text: string, width = COLS): string {
  const glyphs = [...text];
  return glyphs.length <= width ? text : `${glyphs.slice(0, Math.max(0, width - 1)).join("")}…`;
}

/** Empty transcript rows waste an entire G2 text container. */
export function compactOutputLines(text: string): string[] {
  const lines = text.split("\n").filter((line) => line.trim().length > 0);
  return lines.length > 0 ? lines : ["No readable output yet."];
}

/**
 * Turn Host lines into physical G2 rows before choosing the last page. A
 * character-count cap can still wrap in the proportional firmware font.
 */
export function wrapOutputRows(lines: string[]): string[] {
  const rows: string[] = [];
  for (const line of lines) {
    const glyphs = [...line.replace(/\t/g, "    ")];
    let start = 0;
    while (start < glyphs.length) {
      let low = start + 1;
      let high = glyphs.length;
      let end = start + 1;
      while (low <= high) {
        const middle = Math.floor((low + high) / 2);
        if (getTextWidth(glyphs.slice(start, middle).join("")) <= LENS_TEXT_WIDTH) {
          end = middle;
          low = middle + 1;
        } else high = middle - 1;
      }
      if (end < glyphs.length) {
        const minimum = start + Math.floor((end - start) / 2);
        for (let index = end - 1; index > minimum; index -= 1) {
          if (/\s/u.test(glyphs[index]!)) { end = index + 1; break; }
        }
      }
      const row = glyphs.slice(start, end).join("").trimEnd();
      if (row) rows.push(row);
      start = end;
      while (start < glyphs.length && /\s/u.test(glyphs[start]!)) start += 1;
    }
  }
  return rows.length > 0 ? rows : ["No readable output yet."];
}

function frame(lines: string[], footer: string): string {
  const body = lines.slice(0, ROWS - 1).map((line) => pxTruncate(line, LENS_TEXT_WIDTH));
  while (body.length < ROWS - 1) body.push("");
  return [...body, pxTruncate(footer, LENS_TEXT_WIDTH)].join("\n");
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

/** Human-readable kind, since bracketed monospace marks look broken in the proportional firmware face. */
export function harnessLabel(kind?: string): string {
  const key = (kind ?? "").trim().toLowerCase();
  if (key === "codex") return "Codex";
  if (key === "claude") return "Claude";
  if (key === "pi") return "Pi";
  if (["", "agent", "shell", "terminal", "zsh", "bash", "fish"].includes(key)) return "Shell";
  return key.slice(0, 1).toUpperCase() + key.slice(1, 8);
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

/** Plain status words in both the Space row and detail footer. */
const STATUS_LABELS: Record<Agent["status"], string> = {
  working: "WORK", idle: "IDLE", blocked: "QUESTION", failed: "ERROR", done: "DONE", unknown: "?",
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
 * One Space row in reading order. The firmware font is proportional, so
 * padding fields to equal character counts only creates false columns.
 * The number is the visible 1-based voice handle, never a Host id.
 */
export function renderSpaceCard(agent: Agent, selected = false, position = 1): string {
  const status = STATUS_LABELS[agent.status];
  const harness = harnessLabel(agent.kind);
  const host = truncate(agent.hostName || "host", 8);
  const prefix = `${selected ? ">" : " "}${position} ${status} ${harness} · ${host} · `;
  return `${prefix}${truncate(spaceMessage(agent), Math.max(1, COLS - prefix.length))}`;
}

/** One glanceable list with a fixed bottom status row. */
export function renderList(snapshot: Snapshot, selected: number, online: boolean, empty = "no agents", debug?: string, notice: string[] = [], status = "MIC OFF"): string {
  const tail = debug ? [truncate(debug)] : [];
  const head = notice.map((line) => truncate(line));
  const footer = `${status} · ${snapshot.agents.length} Space${snapshot.agents.length === 1 ? "" : "s"}${online ? "" : " · offline"}`;
  if (snapshot.agents.length === 0) return frame([...head, online ? empty : "Host offline", ...tail], footer);
  const visible = windowAround(snapshot.agents, selected, ROWS - 1 - (online ? 0 : 1) - tail.length - head.length);
  const rows = visible.items.map((agent, index) => renderSpaceCard(agent, visible.start + index === selected, visible.start + index + 1));
  return frame([...head, ...(online ? [] : ["Host offline"]), ...rows, ...tail], footer);
}

/** The selected Space's terminal text, using only the G2 navigation gestures. */
export function renderDetail(agent: Agent, output: string[], offset: number, online: boolean, position = 1, notice: string[] = [], status = "MIC OFF"): string {
  const head = notice.map((line) => truncate(line));
  const rows = Math.max(1, OUTPUT_ROWS - head.length);
  const start = Math.max(0, Math.min(offset, Math.max(0, output.length - rows)));
  const visible = output.slice(start, start + rows);
  const range = output.length === 0 ? "0/0" : `${start + visible.length}/${output.length}`;
  return frame([
    ...head,
    truncate(`${position}  ${spaceMessage(agent)} · ${harnessLabel(agent.kind)} · ${agent.hostName || "host"}${online ? "" : " · offline"}`),
    ...visible,
  ], `${status} · ${STATUS_LABELS[agent.status]} · ${range}`);
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
  /**
   * Captured-audio counters: frames seen and kilobytes buffered. Without this
   * a silent microphone and a microphone whose frames never reach the app
   * look identical on the lens.
   */
  audio?: string;
};

export function renderGestureDebug(gesture: GestureDebug): string {
  const mic = [
    gesture.imu ? ` ${gesture.imu}` : "",
    gesture.audio ? ` ${gesture.audio}` : "",
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
