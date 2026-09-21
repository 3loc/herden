/** Bound WebView operations even when the underlying promise ignores abort. */

export interface DeadlineOptions {
  label: string;
  timeoutMs: number;
  signal?: AbortSignal;
}

export async function withAbortDeadline<T>(
  options: DeadlineOptions,
  operation: (signal: AbortSignal) => Promise<T>,
): Promise<T> {
  if (options.signal?.aborted) throw new DOMException(`${options.label} aborted`, "AbortError");
  const controller = new AbortController();
  let rejectDeadline: (reason: Error) => void = () => {};
  const expired = new Promise<never>((_, reject) => { rejectDeadline = reject; });
  const abort = (): void => {
    rejectDeadline(new DOMException(`${options.label} aborted`, "AbortError"));
    controller.abort();
  };
  options.signal?.addEventListener("abort", abort, { once: true });
  if (options.signal?.aborted) abort(); // Covers abort during registration.
  const timer = setTimeout(() => {
    rejectDeadline(new Error(`${options.label} timed out after ${Math.round(options.timeoutMs / 1000)}s`));
    controller.abort();
  }, options.timeoutMs);
  try {
    if (controller.signal.aborted) return await expired;
    return await Promise.race([operation(controller.signal), expired]);
  } finally {
    clearTimeout(timer);
    options.signal?.removeEventListener("abort", abort);
  }
}
