/**
 * Projection from Herden Host state to the compact model the glasses render.
 *
 * The lens shows roughly 400-500 characters, so this layer's job is to throw
 * almost everything away and decide the one thing the HUD cannot decide for
 * itself: whether a change is worth lighting the display for.
 */

/** Attention states, ordered most to least urgent. Order drives the HUD list. */
export const ATTENTION = ["blocked", "failed", "done", "working", "idle", "unknown"];

const STATUS_ALIASES = new Map(
  Object.entries({
    blocked: "blocked",
    waiting: "blocked",
    needs_input: "blocked",
    awaiting_input: "blocked",
    permission_required: "blocked",
    prompted: "working",
    running: "working",
    working: "working",
    busy: "working",
    thinking: "working",
    done: "done",
    complete: "done",
    completed: "done",
    finished: "done",
    idle: "idle",
    ready: "idle",
    error: "failed",
    failed: "failed",
    crashed: "failed",
    exited: "failed",
  }),
);

/** Normalise whatever the Host called it into one of ATTENTION. */
export function normaliseStatus(raw) {
  if (typeof raw !== "string") return "unknown";
  return STATUS_ALIASES.get(raw.trim().toLowerCase()) ?? "unknown";
}

/** Read the first present key from a loosely-shaped record. */
function firstOf(record, ...keys) {
  for (const key of keys) {
    const value = record?.[key];
    if (value !== undefined && value !== null && value !== "") return value;
  }
  return undefined;
}

/**
 * Project one Host agent record. Field spellings are read leniently because the
 * Host API carries no stability guarantee and unknown fields must be ignored.
 */
export function projectAgent(raw) {
  const id = String(firstOf(raw, "pane_id", "paneId", "id", "agent_id") ?? "");
  // Field names verified against a live 0.9.6 Host (protocol 22): status is
  // `agent_status`, the human label is `terminal_title_stripped`, and there is
  // no name field at all — a renamed agent surfaces through the title.
  const name = firstOf(
    raw,
    "name",
    "custom_name",
    "agent_name",
    "terminal_title_stripped",
    "terminal_title",
    "agent",
  );
  return {
    id,
    name: String(name ?? id),
    space: spaceFor(raw),
    status: normaliseStatus(firstOf(raw, "status", "agent_status", "state")),
    pinned: Boolean(firstOf(raw, "pinned", "is_pinned")),
  };
}

/**
 * The lens has no room for a path, and `workspace_id` ("w3T") means nothing to
 * a human. The working directory's last segment is what the wearer recognises.
 */
function spaceFor(raw) {
  const label = firstOf(raw, "workspace", "workspace_label", "label");
  if (label) return String(label);
  const cwd = firstOf(raw, "cwd", "foreground_cwd");
  if (cwd) return String(cwd).replace(/\/+$/, "").split("/").pop() ?? "";
  return String(firstOf(raw, "workspace_id") ?? "");
}

/** Sort by urgency, then pins, then name — the order the HUD lists them in. */
export function orderAgents(agents) {
  const rank = (a) => ATTENTION.indexOf(a.status);
  return [...agents].sort(
    (a, b) =>
      rank(a) - rank(b) ||
      Number(b.pinned) - Number(a.pinned) ||
      a.name.localeCompare(b.name),
  );
}

/** Statuses worth interrupting a walk for. `working` deliberately is not one. */
const WAKE_ON = new Set(["blocked", "failed", "done"]);

/**
 * Decide whether a transition should light the display.
 *
 * Waking on sustained output would turn the lens into a slot machine in the
 * wearer's peripheral vision, so only transitions *into* an attention state
 * count — never repeats of one already showing.
 */
export function shouldWake(previous, next) {
  if (!WAKE_ON.has(next.status)) return false;
  return previous?.status !== next.status;
}

/**
 * Build the whole HUD snapshot, including which agents newly want attention.
 * `previousById` is the last snapshot's agents keyed by id.
 */
export function buildSnapshot(rawAgents, previousById = new Map()) {
  const agents = orderAgents(rawAgents.map(projectAgent).filter((a) => a.id));
  const wake = agents.filter((agent) => shouldWake(previousById.get(agent.id), agent));
  return {
    type: "snapshot",
    at: Date.now(),
    agents,
    wake: wake.map((a) => a.id),
    summary: summarise(agents),
  };
}

/** One line that fits the lens: what the wearer sees on a head-up glance. */
export function summarise(agents) {
  if (agents.length === 0) return "no agents";
  const counts = new Map();
  for (const { status } of agents) counts.set(status, (counts.get(status) ?? 0) + 1);
  return ATTENTION.filter((s) => counts.has(s))
    .map((s) => `${counts.get(s)} ${s}`)
    .join("  ");
}
