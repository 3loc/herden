/** Owns Host connections and their latest proven snapshots. */

import { BridgeClient } from "./client.ts";
import type { ClientOptions } from "./client.ts";
import type { AgentOutput, Command, HostSettings, Snapshot } from "./protocol.ts";

export interface HostConnection {
  readonly online: boolean;
  connect(): void;
  disconnect(): void;
  readOutput(agentId: string): Promise<AgentOutput>;
  send(command: Command): Promise<boolean>;
}

export interface HostServiceOptions {
  onChange: () => void;
  onError?: (message: string) => void;
  clientFactory?: (options: ClientOptions) => HostConnection;
}

export class HostService {
  readonly snapshots = new Map<string, Snapshot>();
  readonly onlineHosts = new Set<string>();
  readonly #options: HostServiceOptions;
  readonly #clients = new Map<string, HostConnection>();
  #generation = 0;

  constructor(options: HostServiceOptions) { this.#options = options; }

  connect(hosts: readonly HostSettings[]): void {
    this.disconnect();
    const generation = this.#generation;
    const factory = this.#options.clientFactory ?? ((options) => new BridgeClient(options));
    for (const host of hosts) {
      const client = factory({
        baseUrl: host.baseUrl, token: host.token,
        onSnapshot: (snapshot) => {
          if (generation !== this.#generation) return;
          this.snapshots.set(host.id, snapshot);
          this.#options.onChange();
        },
        onConnectionChange: (online) => {
          if (generation !== this.#generation) return;
          if (online) this.onlineHosts.add(host.id);
          else this.onlineHosts.delete(host.id);
          this.#options.onChange();
        },
        onCommandError: (message) => {
          if (generation === this.#generation) this.#options.onError?.(message);
        },
      });
      this.#clients.set(host.id, client);
      client.connect();
    }
    this.#options.onChange();
  }

  reconnectOffline(): void {
    for (const client of this.#clients.values()) if (!client.online) client.connect();
  }

  readOutput(hostId: string, agentId: string): Promise<AgentOutput> {
    const client = this.#clients.get(hostId);
    if (!client) return Promise.reject(new Error("Host is unavailable."));
    return client.readOutput(agentId);
  }

  sendCommand(hostId: string, command: Command): Promise<boolean> {
    const client = this.#clients.get(hostId);
    if (!client) return Promise.resolve(false);
    return client.send(command);
  }

  disconnect(): void {
    ++this.#generation;
    for (const client of this.#clients.values()) client.disconnect();
    this.#clients.clear();
    this.snapshots.clear();
    this.onlineHosts.clear();
  }
}
