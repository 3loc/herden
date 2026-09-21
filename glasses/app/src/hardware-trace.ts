/** Temporary, opt-in hardware trace for worn-G2 gesture calibration. */

type TraceValue = string | number | boolean | null;
export type TraceEvent = [number, string, ...TraceValue[]];

export interface TraceOptions {
  endpoint: string;
  session: string;
  post?: (url: string, body: string) => Promise<void>;
  now?: () => number;
}

const MAX_PENDING = 1_000;
const BATCH_SIZE = 2; // The development relay logs only 400 characters per request.

async function postTrace(url: string, body: string): Promise<void> {
  const response = await fetch(url, {
    method: "POST", headers: { "content-type": "application/json" }, body,
    signal: AbortSignal.timeout(3_000),
  });
  if (!response.ok) throw new Error(`trace HTTP ${response.status}`);
}

export class HardwareTrace {
  readonly #endpoint: string;
  readonly #session: string;
  readonly #post: (url: string, body: string) => Promise<void>;
  readonly #now: () => number;
  readonly #pending: TraceEvent[] = [];
  #sending: Promise<void> | null = null;
  #dropped = 0;
  #audioCount = 0;
  #audioBytes = 0;

  constructor(options: TraceOptions) {
    this.#endpoint = options.endpoint;
    this.#session = options.session;
    this.#post = options.post ?? postTrace;
    this.#now = options.now ?? Date.now;
  }

  record(kind: string, ...values: TraceValue[]): void {
    if (this.#pending.length >= MAX_PENDING) {
      this.#pending.shift();
      this.#dropped += 1;
    }
    this.#pending.push([this.#now(), kind, ...values]);
    void this.flush();
  }

  /** Audio payload is private; count callbacks without copying or posting PCM. */
  audioFrame(bytes: number): void {
    this.#audioCount += 1;
    this.#audioBytes += bytes;
  }

  audioSummary(): void {
    if (this.#audioCount === 0) return;
    this.record("audio", this.#audioCount, this.#audioBytes);
    this.#audioCount = 0;
    this.#audioBytes = 0;
  }

  flush(): Promise<void> {
    if (this.#sending) return this.#sending;
    this.#sending = (async () => {
      while (this.#pending.length > 0) {
        const events = this.#pending.slice(0, BATCH_SIZE);
        const body = JSON.stringify({ trace: this.#session, events, dropped: this.#dropped });
        try { await this.#post(this.#endpoint, body); }
        catch { break; } // Keep the batch for the next interval; never block the HUD.
        this.#pending.splice(0, events.length);
        this.#dropped = 0;
      }
    })().finally(() => { this.#sending = null; });
    return this.#sending;
  }
}
