/** Application model: Host projection, selection, and the current lens view. */

import { initialSleepingAttention } from "./attention.ts";
import type { AttentionState } from "./attention.ts";
import { byAttention, outputWindowSize } from "./hud.ts";
import type { Agent, HostSettings, Snapshot } from "./protocol.ts";
import { visibleSnapshot } from "./selection.ts";
import { IDLE_VOICE } from "./voice.ts";
import type { VoiceState } from "./voice.ts";

export type View = "list" | "detail";

/** Pure multi-Host projection. Remote pane IDs remain opaque. */
export function mergeSnapshots(hosts: readonly HostSettings[], sources: ReadonlyMap<string, Snapshot>): Snapshot | null {
  const reports = hosts.flatMap((host) => {
    const snapshot = sources.get(host.id);
    return snapshot ? [{ host, snapshot }] : [];
  });
  if (reports.length === 0) return null;
  const agents = reports.flatMap(({ host, snapshot }) => snapshot.agents.map((agent) => ({
    ...agent, id: `${host.id}:${agent.id}`, hostId: host.id, hostName: host.name, remoteId: agent.id,
  }))).sort(byAttention);
  const wake = reports.flatMap(({ host, snapshot }) => snapshot.wake.map((id) => `${host.id}:${id}`));
  return {
    protocol_version: 1, type: "snapshot", revision: Math.max(...reports.map(({ snapshot }) => snapshot.revision)),
    at: Date.now(), inventory_valid: reports.every(({ snapshot }) => snapshot.inventory_valid),
    stale: reports.some(({ snapshot }) => snapshot.stale),
    controls_allowed: reports.some(({ snapshot }) => snapshot.controls_allowed), agents, wake,
    summary: `${agents.length} Space${agents.length === 1 ? "" : "s"}`,
  };
}

export class HudModel {
  view: View = "list";
  selected = 0;
  userSelected = false;
  online = false;
  snapshot: Snapshot | null = null;
  roster: Snapshot | null = null;
  hosts: HostSettings[] = [];
  output: string[] = [];
  outputOffset = 0;
  outputLoading = false;
  voice: VoiceState = IDLE_VOICE;
  attention: AttentionState;
  /** Any navigation/sleep invalidates an earlier asynchronous output read. */
  outputRequest = 0;

  constructor(now: number = Date.now()) {
    this.attention = initialSleepingAttention(now);
  }

  selectedAgent(): Agent | null { return this.snapshot?.agents[this.selected] ?? null; }

  refresh(sources: ReadonlyMap<string, Snapshot>, onlineHosts: ReadonlySet<string>, hidden: ReadonlySet<string>): void {
    const previousId = this.selectedAgent()?.id;
    this.roster = mergeSnapshots(this.hosts, sources);
    this.snapshot = this.roster ? visibleSnapshot(this.roster, new Set(hidden)) : null;
    this.online = onlineHosts.size > 0;
    const moved = this.snapshot?.agents.findIndex((agent) => agent.id === previousId) ?? -1;
    this.selected = this.userSelected && moved >= 0 ? moved : 0;
  }

  showList(): void {
    this.invalidateOutput();
    this.view = "list";
    this.output = [];
    this.outputOffset = 0;
  }

  selectPosition(position: number): boolean {
    const index = position - 1;
    if (index < 0 || index >= (this.snapshot?.agents.length ?? 0)) return false;
    this.userSelected = true;
    this.selected = index;
    return true;
  }

  scroll(direction: -1 | 1): void { this.move(direction, 1); }

  /** A page is eight physical G2 rows, leaving one list row of overlap. */
  page(direction: -1 | 1): void { this.move(direction, outputWindowSize()); }

  private move(direction: -1 | 1, distance: number): void {
    if (this.view === "list") {
      this.userSelected = true;
      this.selected = Math.max(0, Math.min((this.snapshot?.agents.length ?? 1) - 1, this.selected + direction * distance));
    } else {
      this.outputOffset = Math.max(0, Math.min(Math.max(0, this.output.length - outputWindowSize()), this.outputOffset + direction * distance));
    }
  }

  beginOutput(): number {
    this.outputLoading = true;
    return ++this.outputRequest;
  }

  setOutput(lines: string[]): void {
    this.view = "detail";
    this.output = lines;
    this.outputOffset = Math.max(0, lines.length - outputWindowSize());
  }

  /** Live output follows the end unless the wearer has scrolled back. */
  updateOutput(lines: string[]): boolean {
    if (lines.length === this.output.length && lines.every((line, index) => line === this.output[index])) return false;
    const oldBottom = Math.max(0, this.output.length - outputWindowSize());
    const following = this.outputOffset >= oldBottom;
    this.output = lines;
    const newBottom = Math.max(0, lines.length - outputWindowSize());
    this.outputOffset = following ? newBottom : Math.min(this.outputOffset, newBottom);
    return true;
  }

  invalidateOutput(): void {
    this.outputRequest += 1;
    this.outputLoading = false;
  }
}
