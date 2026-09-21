/**
 * Talks to `glasses/bridge` on the Host: SSE in, POST out.
 *
 * `EventSource` handles its own reconnection, which is the point — the wearer
 * is walking through patchy coverage and nothing here should need a restart to
 * come back. The Even Hub network whitelist in `app.json` must name this
 * origin, and the bridge must answer with CORS headers; the whitelist is a
 * permission check, not a CORS bypass.
 */

import type { AgentOutput, Command, Snapshot } from "./protocol";
import { withAbortDeadline } from "./deadline.ts";

export const HOST_IO_TIMEOUT_MS = 6_000;

export interface ClientOptions {
  baseUrl: string;
  token: string;
  onSnapshot: (snapshot: Snapshot) => void;
  onConnectionChange?: (online: boolean) => void;
  onCommandError?: (message: string) => void;
  /** Override only for deterministic tests. */
  requestTimeoutMs?: number;
}

export class BridgeClient {
  #options: ClientOptions;
  #source: EventSource | null = null;
  #online = false;

  constructor(options: ClientOptions) {
    this.#options = options;
  }

  get online(): boolean {
    return this.#online;
  }

  connect(): void {
    this.disconnect();
    const { baseUrl, token, onSnapshot } = this.#options;
    const url = `${baseUrl.replace(/\/$/, "")}/events?token=${encodeURIComponent(token)}`;
    const source = new EventSource(url);

    source.onopen = () => this.#setOnline(true);
    source.onerror = () => this.#setOnline(false); // EventSource retries by itself.
    source.onmessage = (event) => {
      let snapshot: Snapshot;
      try {
        snapshot = JSON.parse(event.data) as Snapshot;
      } catch {
        return; // Parse leniently; a bad frame must not kill the stream.
      }
      this.#setOnline(true);
      if (snapshot.type === "snapshot") onSnapshot(snapshot);
    };

    this.#source = source;
  }

  disconnect(): void {
    this.#source?.close();
    this.#source = null;
  }

  /** Send one explicit control gesture and surface failures to the phone UI. */
  async send(command: Command): Promise<boolean> {
    const { baseUrl, token, requestTimeoutMs = HOST_IO_TIMEOUT_MS } = this.#options;
    try {
      return await withAbortDeadline({ label: "Host command", timeoutMs: requestTimeoutMs }, async (signal) => {
        const response = await fetch(`${baseUrl.replace(/\/$/, "")}/command`, {
          method: "POST",
          headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
          body: JSON.stringify(command), signal,
        });
        if (signal.aborted) return false;
        if (response.ok) return true;
        const payload = await response.json().catch(() => ({})) as { error?: string };
        if (signal.aborted) return false;
        this.#options.onCommandError?.(payload.error ?? "Command was not delivered.");
        return false;
      });
    } catch {
      this.#options.onCommandError?.("Delivery is uncertain. Do not automatically retry.");
      return false;
    }
  }

  /** Read bounded, text-only output for the Agent the wearer selected. */
  async readOutput(agentId: string): Promise<AgentOutput> {
    const { baseUrl, token, requestTimeoutMs = HOST_IO_TIMEOUT_MS } = this.#options;
    const url = `${baseUrl.replace(/\/$/, "")}/agent-output?agent=${encodeURIComponent(agentId)}`;
    return withAbortDeadline({ label: "Host output", timeoutMs: requestTimeoutMs }, async (signal) => {
      const response = await fetch(url, { headers: { authorization: `Bearer ${token}` }, signal });
      const payload = await response.json().catch(() => ({})) as Partial<AgentOutput> & { error?: string };
      if (!response.ok || typeof payload.text !== "string" || (payload.source !== "recent" && payload.source !== "visible")) {
        throw new Error(payload.error ?? "Output is unavailable.");
      }
      return { agent_id: payload.agent_id ?? agentId, text: payload.text, source: payload.source };
    });
  }

  #setOnline(online: boolean): void {
    if (online === this.#online) return;
    this.#online = online;
    this.#options.onConnectionChange?.(online);
  }
}
