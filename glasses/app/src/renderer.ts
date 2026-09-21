/**
 * Last-frame-wins rendering for an SDK whose update callback can disappear.
 *
 * Callers only publish desired frames. They never wait for the lens: a slow or
 * broken display must not hold voice recognition, navigation, or Host I/O.
 */

export class RenderTimeoutError extends Error {
  override readonly name = "RenderTimeoutError";
  readonly timeoutMs: number;

  constructor(timeoutMs: number) {
    super(`lens update timed out after ${timeoutMs}ms`);
    this.timeoutMs = timeoutMs;
  }
}

export interface LatestFrameRendererOptions<Frame> {
  write: (frame: Frame) => Promise<void>;
  /** Image pages may opt into one full rebuild. Text pages should not. */
  rebuild?: () => Promise<void>;
  timeoutMs: number;
  onError?: (error: unknown) => void;
  onRendered?: (frame: Frame) => void;
}

interface DesiredFrame<Frame> {
  readonly revision: number;
  readonly frame: Frame;
}

async function bounded<T>(work: Promise<T>, timeoutMs: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new RenderTimeoutError(timeoutMs)), timeoutMs);
  });
  try {
    return await Promise.race([work, timeout]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

/**
 * Serialises frame writes without forming an immortal promise chain.
 *
 * A timeout gets exactly one container rebuild and one retry of the newest
 * frame. If that retry also fails, this run ends; a later requested frame can
 * start a fresh run instead of queueing behind the abandoned SDK promise.
 */
export class LatestFrameRenderer<Frame> {
  readonly #options: LatestFrameRendererOptions<Frame>;
  #desired: DesiredFrame<Frame> | undefined;
  #revision = 0;
  #attemptedRevision = 0;
  #rendered: Frame | undefined;
  #hasRendered = false;
  #active: Promise<void> | null = null;

  constructor(options: LatestFrameRendererOptions<Frame>) {
    this.#options = options;
  }

  request(frame: Frame): void {
    if (this.#active && this.#desired && Object.is(this.#desired.frame, frame)) return;
    if (!this.#active && this.#hasRendered && Object.is(this.#rendered, frame)) return;
    this.#desired = { revision: ++this.#revision, frame };
    this.#start();
  }

  /** Test and shutdown seam: resolves after all currently requested work. */
  async flush(): Promise<void> {
    while (this.#active) {
      const active = this.#active;
      await active;
      // The completion handler may have started work for a request which
      // arrived on the last turn of the previous drain.
      await Promise.resolve();
      if (this.#active === active) return;
    }
  }

  #start(): void {
    if (this.#active) return;
    const active = this.#drain();
    this.#active = active;
    void active.finally(() => {
      if (this.#active !== active) return;
      this.#active = null;
      if (this.#desired && this.#desired.revision > this.#attemptedRevision) this.#start();
    });
  }

  async #write(desired: DesiredFrame<Frame>): Promise<{ ok: true } | { ok: false; error: unknown }> {
    this.#attemptedRevision = desired.revision;
    const work = Promise.resolve().then(() => this.#options.write(desired.frame));
    try {
      await bounded(work, this.#options.timeoutMs);
      this.#rendered = desired.frame;
      this.#hasRendered = true;
      this.#options.onRendered?.(desired.frame);
      return { ok: true };
    } catch (error) {
      this.#options.onError?.(error);
      if (error instanceof RenderTimeoutError) {
        // The SDK promise cannot be cancelled. If it eventually resumes, it
        // may finish painting stale tiles over the recovered frame. Reassert
        // whatever is newest after that late write has completely settled.
        void work.then(() => this.#reassertAfterLateWrite(desired), () => {});
      }
      return { ok: false, error };
    }
  }

  #reassertAfterLateWrite(stale: DesiredFrame<Frame>): void {
    const latest = this.#desired;
    if (!latest || latest.revision <= stale.revision) return;
    this.#desired = { revision: ++this.#revision, frame: latest.frame };
    this.#start();
  }

  async #drain(): Promise<void> {
    let desired = this.#desired;
    if (!desired) return;
    let result = await this.#write(desired);
    if (result.ok) {
      while (this.#desired && this.#desired.revision > desired.revision) {
        desired = this.#desired;
        result = await this.#write(desired);
        if (!result.ok) return;
      }
      return;
    }

    // Only image callers which explicitly provide a recovery hook rebuild the
    // page. Native text updates must never tear down a healthy page because a
    // delayed bridge callback would otherwise blank one side of the display.
    if (!(result.error instanceof RenderTimeoutError) || !this.#options.rebuild) return;
    try {
      await bounded(this.#options.rebuild(), this.#options.timeoutMs);
    } catch (error) {
      this.#options.onError?.(error);
      return;
    }

    desired = this.#desired;
    if (desired) await this.#write(desired);
  }
}
