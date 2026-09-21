/** Native firmware text view. Rendering never blocks the controller. */

import {
  CreateStartUpPageContainer, TextContainerProperty, TextContainerUpgrade,
} from "@evenrealities/even_hub_sdk";
import type { EvenAppBridge } from "@evenrealities/even_hub_sdk";
import { LatestFrameRenderer } from "./renderer.ts";

const CONTAINER_ID = 1;
const RENDER_TIMEOUT_MS = 2_500;

export interface LensBridge {
  createStartUpPageContainer: EvenAppBridge["createStartUpPageContainer"];
  textContainerUpgrade: EvenAppBridge["textContainerUpgrade"];
}

export interface LensEvents {
  onWrite?: () => void;
  onRebuild?: () => void;
  onError?: (error: unknown) => void;
  onRendered?: (content: string) => void;
}

function page(): { containerTotalNum: number; textObject: TextContainerProperty[] } {
  return {
    containerTotalNum: 1,
    textObject: [new TextContainerProperty({
      containerID: CONTAINER_ID, containerName: "herden-main", xPosition: 0, yPosition: 0,
      width: 576, height: 288, isEventCapture: 1, paddingLength: 0,
      borderWidth: 0, borderColor: 0, content: " ",
    })],
  };
}

export class NativeLensView {
  readonly #bridge: LensBridge;
  readonly #events: LensEvents;
  readonly #renderer: LatestFrameRenderer<string>;

  constructor(bridge: LensBridge, events: LensEvents = {}) {
    this.#bridge = bridge;
    this.#events = events;
    this.#renderer = new LatestFrameRenderer<string>({
      write: (content) => this.#upgrade(content),
      timeoutMs: RENDER_TIMEOUT_MS,
      onError: events.onError,
      onRendered: events.onRendered,
    });
  }

  async initialize(): Promise<void> {
    const created = await this.#bridge.createStartUpPageContainer(new CreateStartUpPageContainer(page()));
    if (created === 0) return;
    // SDK result 1 means invalid, not "already exists". Rebuilding on that
    // code can blank a healthy eye; fail visibly rather than mutating the page.
    const label = ({ 1: "invalid container", 2: "oversize", 3: "out of memory" } as Record<number, string>)[created]
      ?? `code ${created}`;
    throw new Error(`failed to create the HUD page: ${label}`);
  }

  show(content: string): void { this.#renderer.request(content); }

  async flush(): Promise<void> { await this.#renderer.flush(); }

  async #upgrade(content: string): Promise<void> {
    this.#events.onWrite?.();
    const updated = await this.#bridge.textContainerUpgrade(new TextContainerUpgrade({
      containerID: CONTAINER_ID, containerName: "herden-main",
      contentOffset: 0, contentLength: 0,
      // Empty content is rejected by some firmware versions.
      content: content.length === 0 ? " " : content,
    }));
    if (!updated) throw new Error("native text update failed");
  }
}
