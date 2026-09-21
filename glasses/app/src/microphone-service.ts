/** Serialises Hub mic control so a late open cannot survive a sleep request. */

import { AudioInputSource } from "@evenrealities/even_hub_sdk";

export interface AudioBridge {
  audioControl(enable: boolean, source?: AudioInputSource): Promise<boolean>;
}

export class MicrophoneService {
  readonly #bridge: AudioBridge;
  #tail: Promise<void> = Promise.resolve();
  #wanted = false;
  #open = false;
  #generation = 0;

  constructor(bridge: AudioBridge) { this.#bridge = bridge; }

  get wanted(): boolean { return this.#wanted; }

  /** Returns false if a concurrent stop superseded this start. */
  start(): Promise<boolean> {
    this.#wanted = true;
    const generation = ++this.#generation;
    return this.#queue(async () => {
      if (generation !== this.#generation || !this.#wanted) return false;
      if (!this.#open) {
        if (!await this.#bridge.audioControl(true, AudioInputSource.Glasses)) {
          throw new Error("the glasses mic did not open");
        }
        this.#open = true;
      }
      return generation === this.#generation && this.#wanted;
    });
  }

  /** Also closes an open which was still in flight when stop was requested. */
  stop(): Promise<void> {
    this.#wanted = false;
    ++this.#generation;
    return this.#queue(async () => {
      // Always send off: a fresh WebView can inherit capture from its predecessor.
      const wasOpen = this.#open;
      try {
        let closed = await this.#bridge.audioControl(false);
        // A refused close after a confirmed open is not "already off". Retry
        // once and surface a persistent refusal instead of silently claiming
        // that recording stopped.
        if (!closed && wasOpen) closed = await this.#bridge.audioControl(false);
        if (!closed && wasOpen) throw new Error("the glasses mic may still be recording");
      } finally { this.#open = false; }
    });
  }

  #queue<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.#tail.then(operation, operation);
    this.#tail = result.then(() => {}, () => {});
    return result;
  }
}
