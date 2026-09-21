/** Ordered, session-scoped continuous-voice work. No SDK imports. */

import { encodeWav } from "./audio.ts";
import { parseCommand } from "./commands.ts";
import type { VoiceCommand } from "./commands.ts";
import { containsSpeech } from "./listen.ts";

export interface VoiceSession {
  readonly generation: number;
  readonly signal?: AbortSignal;
  isCurrent(): boolean;
}

/**
 * Preserves capture order while making an old microphone session inert.
 * Starting or stopping invalidates every queued and in-flight result.
 */
export class OrderedVoiceQueue {
  #generation = 0;
  #open = false;
  #pending = 0;
  #queue: Promise<void> = Promise.resolve();
  #abort = new AbortController();

  get pending(): number { return this.#pending; }
  get open(): boolean { return this.#open; }

  start(): void {
    this.#abort.abort();
    this.#abort = new AbortController();
    this.#generation += 1;
    this.#open = true;
    this.#pending = 0;
    this.#queue = Promise.resolve();
  }

  stop(): void {
    this.#abort.abort();
    this.#open = false;
    this.#generation += 1;
    this.#pending = 0;
    this.#queue = Promise.resolve();
  }

  enqueue(frames: Uint8Array[], run: (frames: Uint8Array[], session: VoiceSession) => Promise<void>): void {
    const generation = this.#generation;
    const session: VoiceSession = {
      generation,
      signal: this.#abort.signal,
      isCurrent: () => this.#open && generation === this.#generation,
    };
    this.#pending += 1;
    this.#queue = this.#queue.catch(() => {}).then(async () => {
      if (session.isCurrent()) await run(frames, session);
    }).finally(() => {
      if (generation === this.#generation) this.#pending = Math.max(0, this.#pending - 1);
    });
  }

  async flush(): Promise<void> { await this.#queue; }
}

export interface ProcessVoiceUtteranceOptions {
  session: VoiceSession;
  transcribe: (wav: Uint8Array, signal?: AbortSignal) => Promise<string>;
  onTranscribing: () => void;
  onResolved: (text: string, command: VoiceCommand) => void;
  onFailed: (message: string) => void;
  execute: (command: VoiceCommand, session: VoiceSession) => Promise<void>;
  noteActivity: () => void;
}

function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** Transcribe, parse and execute one endpointed clip without touching paint. */
export async function processVoiceUtterance(
  frames: Uint8Array[],
  options: ProcessVoiceUtteranceOptions,
): Promise<void> {
  const { session } = options;
  if (!session.isCurrent() || !containsSpeech(frames)) return;
  options.onTranscribing();
  try {
    const text = await options.transcribe(encodeWav(frames), session.signal);
    if (!session.isCurrent()) return;
    if (text.length === 0) { options.onFailed("nothing recognised"); return; }
    const command = parseCommand(text);
    options.onResolved(text, command);
    await options.execute(command, session);
    // Slow Host work must not consume the ordinary post-command idle period.
    if (session.isCurrent() && command.type !== "unknown") options.noteActivity();
  } catch (error) {
    if (!session.isCurrent()) return;
    options.onFailed(message(error));
  }
}
