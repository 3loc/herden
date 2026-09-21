/**
 * Which Spaces reach the lens. The phone panel keeps showing every Space; the
 * lens shows only the chosen ones.
 *
 * HIDDEN ids are stored, never visible ones: a Space that appears after the
 * choice was made must show up rather than silently vanish. Ids are the
 * projected `${hostId}:${remoteId}`, stable across restarts, and an id whose
 * Space no longer exists is simply carried along.
 */

import type { Snapshot } from "./protocol";

/** Local storage holds whatever the last release wrote; parse leniently. */
export function parseHiddenSpaces(raw: string | null | undefined): Set<string> {
  try {
    const ids = JSON.parse(raw ?? "[]") as unknown;
    if (!Array.isArray(ids)) return new Set();
    return new Set(ids.filter((id): id is string => typeof id === "string" && id.length > 0));
  } catch {
    return new Set();
  }
}

export function serialiseHiddenSpaces(hidden: Set<string>): string {
  return JSON.stringify([...hidden].sort());
}

/** The projection the lens renders: hidden Spaces leave the list and the wake. */
export function visibleSnapshot(snapshot: Snapshot, hidden: Set<string>): Snapshot {
  if (hidden.size === 0) return snapshot;
  const agents = snapshot.agents.filter((agent) => !hidden.has(agent.id));
  return {
    ...snapshot, agents, wake: snapshot.wake.filter((id) => !hidden.has(id)),
    summary: `${agents.length} Space${agents.length === 1 ? "" : "s"}`,
  };
}
