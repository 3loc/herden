/** HUD protocol v1 and the client-side multi-Host projection. */

export const HUD_PROTOCOL_VERSION = 1;

export type Attention = "blocked" | "failed" | "done" | "working" | "idle" | "unknown";

export interface Agent {
  id: string;
  name: string;
  /** Host supplied interactive Agent kind: claude, codex, pi, or agent. */
  kind?: string;
  space: string;
  status: Attention;
  pinned: boolean;
  /** Filled by the glasses app when a snapshot is merged from a Host. */
  hostId?: string;
  hostName?: string;
  /** The opaque pane id used only when issuing a command back to its Host. */
  remoteId?: string;
}

export interface Snapshot {
  protocol_version: typeof HUD_PROTOCOL_VERSION;
  type: "snapshot";
  revision: number;
  at: number;
  inventory_valid: boolean;
  stale: boolean;
  controls_allowed: boolean;
  agents: Agent[];
  wake: string[];
  summary: string;
}

/** Bounded recent terminal text for one selected Agent. */
export interface AgentOutput {
  agent_id: string;
  text: string;
  /** `recent` for an idle Agent, `visible` while a TUI is working. */
  source: "recent" | "visible";
}

/** Stored only in Even local storage; each Host retains its own bearer token. */
export interface HostSettings {
  id: string;
  name: string;
  baseUrl: string;
  token: string;
}

export type Command =
  | { action: "send_enter"; agentId: string }
  | { action: "interrupt"; agentId: string };
