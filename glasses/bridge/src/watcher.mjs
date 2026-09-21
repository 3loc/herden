/**
 * Keeps a current HUD snapshot of the Host's agents and emits it on change.
 *
 * The cycle is snapshot-then-subscribe, repeated from scratch on every
 * reconnect. Pane-scoped subscriptions are derived from the snapshot they were
 * taken with and die with their connection: reusing pane ids across a reconnect
 * is what lets one exited pane wedge the whole subscription with
 * `pane_not_found` and take the HUD offline until restart.
 *
 * A slow `agent.list` poll runs alongside as a safety net. Missing a state
 * change is worse here than an extra RPC — the wearer is on a walk with no
 * other way to notice.
 */

import { EventEmitter } from "node:events";
import { call, subscribe } from "./herden.mjs";
import { buildSnapshot } from "./hud.mjs";

/**
 * Pane-scoped subscription types we care about. The discriminator is `type`,
 * verified against a live 0.9.6 Host's `herden api schema --json`; a `kind` key
 * is rejected with `invalid_request: missing field 'type'`.
 *
 * `pane.updated` is deliberately absent: it fires on every terminal-title
 * change (~4/s) and is pure noise here.
 */
const PANE_KINDS = ["pane.agent_status_changed"];

const RESUBSCRIBE_MIN_MS = 500;
const RESUBSCRIBE_MAX_MS = 15_000;

export class AgentWatcher extends EventEmitter {
  #socketPath;
  #pollMs;
  #snapshot = null;
  #previousById = new Map();
  #session = null;
  #pollTimer = null;
  #retryTimer = null;
  #backoff = RESUBSCRIBE_MIN_MS;
  #stopped = false;

  constructor({ socketPath, pollMs = 15_000 }) {
    super();
    this.#socketPath = socketPath;
    this.#pollMs = pollMs;
  }

  get snapshot() {
    return this.#snapshot;
  }

  async start() {
    this.#stopped = false;
    await this.#cycle();
    this.#pollTimer = setInterval(() => {
      this.#refresh().catch((err) => this.emit("warn", err));
    }, this.#pollMs);
    this.#pollTimer.unref?.();
  }

  stop() {
    this.#stopped = true;
    clearInterval(this.#pollTimer);
    clearTimeout(this.#retryTimer);
    this.#session?.close();
    this.#session = null;
  }

  /** Snapshot, then take a fresh pane-scoped subscription against it. */
  async #cycle() {
    if (this.#stopped) return;
    this.#session?.close();
    this.#session = null;

    let agents;
    try {
      agents = await this.#refresh();
    } catch (err) {
      this.emit("warn", err);
      return this.#retryLater();
    }

    const subscriptions = agents.flatMap((agent) =>
      PANE_KINDS.map((type) => ({ type, pane_id: agent.id })),
    );
    if (subscriptions.length === 0) return this.#retryLater();

    this.#session = subscribe(this.#socketPath, subscriptions, {
      onEvent: () => {
        // The payload only says something moved; re-read rather than trust it.
        this.#refresh().catch((err) => this.emit("warn", err));
      },
      onError: (err) => {
        this.emit("warn", err);
        this.#retryLater();
      },
      onClose: () => this.#retryLater(),
    });
    this.#backoff = RESUBSCRIBE_MIN_MS;
    this.emit("connected");
  }

  #retryLater() {
    if (this.#stopped || this.#retryTimer) return;
    const delay = this.#backoff;
    this.#backoff = Math.min(this.#backoff * 2, RESUBSCRIBE_MAX_MS);
    this.#retryTimer = setTimeout(() => {
      this.#retryTimer = null;
      this.#cycle().catch((err) => this.emit("warn", err));
    }, delay);
    this.#retryTimer.unref?.();
  }

  /** Pull `agent.list`, rebuild the snapshot, emit only when something changed. */
  async #refresh() {
    const result = await call(this.#socketPath, "agent.list");
    const raw = Array.isArray(result?.agents) ? result.agents : (result ?? []);
    const snapshot = buildSnapshot(raw, this.#previousById);

    const changed =
      JSON.stringify(snapshot.agents) !== JSON.stringify(this.#snapshot?.agents ?? null);
    this.#previousById = new Map(snapshot.agents.map((a) => [a.id, a]));
    this.#snapshot = snapshot;
    if (changed || snapshot.wake.length > 0) this.emit("snapshot", snapshot);
    return snapshot.agents;
  }
}
