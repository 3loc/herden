/**
 * Speech to text for the captured clip.
 *
 * The Even Hub SDK has no speech recognition, so the WAV goes to a
 * transcription service. The default base URL is `/stt` relative to the app
 * origin, which the development server proxies; `VITE_HERDEN_HUD_STT` points
 * a packaged build somewhere else. No service address belongs in this app.
 */

/** `import.meta.env` is absent under plain `node --test`; the tests import this module. */
const ENV: Record<string, string | undefined> = (import.meta as { env?: Record<string, string | undefined> }).env ?? {};

export const STT_BASE_URL: string = (ENV.VITE_HERDEN_HUD_STT ?? "/stt").replace(/\/$/, "");

/**
 * A stuck upload must never wedge the queue.
 *
 * Observed on a real G2 (2026-09-19): `FormData` + `Blob` uploads from the
 * Even app's WebView never settled — no response, no rejection — and because
 * utterances transcribe serially every later phrase queued behind the first
 * one, so the HUD sat in `transcribing` forever while the microphone kept
 * capturing. The body is therefore assembled by hand, and every request
 * carries a deadline.
 */
export const STT_TIMEOUT_MS = 12_000;

export interface TranscribeOptions {
  baseUrl?: string;
  language?: string;
  signal?: AbortSignal;
  timeoutMs?: number;
}

const BOUNDARY = "herdenhud6c8a1f2e";

function ascii(text: string): Uint8Array {
  const bytes = new Uint8Array(text.length);
  for (let index = 0; index < text.length; index += 1) bytes[index] = text.charCodeAt(index) & 0x7f;
  return bytes;
}

/**
 * One multipart/form-data body, built as bytes rather than through FormData.
 * Exported so the exact wire bytes can be asserted in a test.
 */
export function multipartBody(
  wav: Uint8Array,
  fields: Readonly<Record<string, string>> = {},
  boundary: string = BOUNDARY,
): Uint8Array {
  const head = ascii(
    `--${boundary}\r\n`
    + 'Content-Disposition: form-data; name="file"; filename="command.wav"\r\n'
    + "Content-Type: audio/wav\r\n\r\n",
  );
  const extras = ascii(
    Object.entries(fields)
      .map(([name, value]) => `\r\n--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}`)
      .join(""),
  );
  const tail = ascii(`\r\n--${boundary}--\r\n`);
  const body = new Uint8Array(head.length + wav.length + extras.length + tail.length);
  body.set(head, 0);
  body.set(wav, head.length);
  body.set(extras, head.length + wav.length);
  body.set(tail, head.length + wav.length + extras.length);
  return body;
}

export function multipartContentType(boundary: string = BOUNDARY): string {
  return `multipart/form-data; boundary=${boundary}`;
}

/** Post one WAV clip and return the recognised text, trimmed. */
export async function transcribe(wav: Uint8Array, options: TranscribeOptions = {}): Promise<string> {
  const base = (options.baseUrl ?? STT_BASE_URL).replace(/\/$/, "");
  const fields: Record<string, string> = options.language ? { language: options.language } : {};
  const body = multipartBody(wav, fields);
  const deadline = new AbortController();
  const timeoutMs = options.timeoutMs ?? STT_TIMEOUT_MS;
  const timer = setTimeout(() => deadline.abort(), timeoutMs);
  const abort = (): void => deadline.abort();
  options.signal?.addEventListener("abort", abort);
  // Raced rather than merely aborted: a WebView whose fetch ignores the abort
  // signal would otherwise hang forever, which is the failure this exists for.
  let expire: (reason: Error) => void = () => {};
  const expired = new Promise<never>((_, reject) => {
    expire = reject;
  });
  const timer2 = setTimeout(
    () => expire(new Error(`transcribe timed out after ${Math.round(timeoutMs / 1000)}s`)),
    timeoutMs,
  );
  try {
    const response = await Promise.race([
      fetch(`${base}/v1/transcribe`, {
        method: "POST",
        body: body.slice().buffer as ArrayBuffer,
        headers: { "content-type": multipartContentType() },
        signal: deadline.signal,
      }),
      expired,
    ]);
    if (!response.ok) throw new Error(`transcribe failed: ${response.status}`);
    const payload = await response.json().catch(() => ({})) as { text?: unknown; error?: unknown };
    if (typeof payload.text !== "string") {
      throw new Error(typeof payload.error === "string" ? payload.error : "no transcript returned");
    }
    return payload.text.trim();
  } catch (error) {
    if (deadline.signal.aborted && !options.signal?.aborted) {
      throw new Error(`transcribe timed out after ${Math.round(timeoutMs / 1000)}s`);
    }
    throw error;
  } finally {
    clearTimeout(timer);
    clearTimeout(timer2);
    options.signal?.removeEventListener("abort", abort);
  }
}
