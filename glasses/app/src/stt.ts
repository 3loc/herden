/**
 * Speech to text for the captured clip.
 *
 * The Even Hub SDK has no speech recognition, so the WAV goes to a
 * transcription service. The default base URL is `/stt` relative to the app
 * origin, which the development server proxies; `VITE_HERDEN_HUD_STT` points
 * a packaged build somewhere else. No service address belongs in this app.
 */

export const STT_BASE_URL: string = (import.meta.env.VITE_HERDEN_HUD_STT ?? "/stt").replace(/\/$/, "");

export interface TranscribeOptions {
  baseUrl?: string;
  language?: string;
  signal?: AbortSignal;
}

/** Post one WAV clip and return the recognised text, trimmed. */
export async function transcribe(wav: Uint8Array, options: TranscribeOptions = {}): Promise<string> {
  const base = (options.baseUrl ?? STT_BASE_URL).replace(/\/$/, "");
  const form = new FormData();
  // Copy into a plain ArrayBuffer: a Uint8Array view may be a slice.
  form.append("file", new Blob([wav.slice().buffer as ArrayBuffer], { type: "audio/wav" }), "command.wav");
  if (options.language) form.append("language", options.language);
  const response = await fetch(`${base}/v1/transcribe`, { method: "POST", body: form, signal: options.signal });
  if (!response.ok) throw new Error(`transcribe failed: ${response.status}`);
  const payload = await response.json().catch(() => ({})) as { text?: unknown; error?: unknown };
  if (typeof payload.text !== "string") throw new Error(typeof payload.error === "string" ? payload.error : "no transcript returned");
  return payload.text.trim();
}
