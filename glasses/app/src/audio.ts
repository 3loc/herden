/**
 * Glasses microphone PCM to a WAV container. No SDK imports, so it is
 * testable in Node.
 *
 * The transcription service decodes wav, flac and ogg-opus, so the raw frames
 * the Hub pushes need a container before they can be posted anywhere.
 */

/**
 * ASSUMPTION, to verify on hardware: the Even Hub declares no sample rate for
 * `audioEvent.audioPcm`, so the whole app treats glasses microphone audio as
 * 16 kHz mono signed 16-bit little-endian PCM. If speech ever transcribes at
 * the wrong speed or pitch, this constant is the first thing to change.
 */
export const PCM_FORMAT = { sampleRate: 16_000, channels: 1, bitsPerSample: 16 } as const;

/** A RIFF/WAVE header for uncompressed PCM is exactly this long. */
export const WAV_HEADER_BYTES = 44;

/** Shorter than this and the clip is a stray press, not a spoken command. */
export const MIN_CLIP_MS = 200;

export function pcmDurationMs(byteLength: number): number {
  const bytesPerSecond = PCM_FORMAT.sampleRate * PCM_FORMAT.channels * (PCM_FORMAT.bitsPerSample / 8);
  return (byteLength / bytesPerSecond) * 1000;
}

/**
 * The host may hand PCM over as bytes, as a JSON number array, or as base64.
 * Parse leniently: an unreadable frame is dropped rather than throwing inside
 * the event callback.
 */
export function toPcmBytes(value: unknown): Uint8Array {
  if (value instanceof Uint8Array) return value;
  if (Array.isArray(value)) return Uint8Array.from(value as number[], (byte) => Number(byte) & 0xff);
  if (typeof value === "string") {
    try {
      const binary = atob(value);
      return Uint8Array.from(binary, (character) => character.codePointAt(0) ?? 0);
    } catch { return new Uint8Array(0); }
  }
  return new Uint8Array(0);
}

export function concatPcm(chunks: readonly Uint8Array[]): Uint8Array {
  const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const joined = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { joined.set(chunk, offset); offset += chunk.length; }
  return joined;
}

/** Concatenate the captured frames and prefix a 44-byte RIFF/WAVE header. */
export function encodeWav(chunks: readonly Uint8Array[], format = PCM_FORMAT): Uint8Array {
  const data = concatPcm(chunks);
  const blockAlign = format.channels * (format.bitsPerSample / 8);
  const wav = new Uint8Array(WAV_HEADER_BYTES + data.length);
  const view = new DataView(wav.buffer);
  const ascii = (offset: number, text: string): void => {
    for (let index = 0; index < text.length; index += 1) view.setUint8(offset + index, text.charCodeAt(index));
  };
  ascii(0, "RIFF");
  view.setUint32(4, 36 + data.length, true); // Everything after this field.
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  view.setUint32(16, 16, true); // PCM fmt chunk length.
  view.setUint16(20, 1, true); // 1 = uncompressed PCM.
  view.setUint16(22, format.channels, true);
  view.setUint32(24, format.sampleRate, true);
  view.setUint32(28, format.sampleRate * blockAlign, true); // Byte rate.
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, format.bitsPerSample, true);
  ascii(36, "data");
  view.setUint32(40, data.length, true);
  wav.set(data, WAV_HEADER_BYTES);
  return wav;
}
