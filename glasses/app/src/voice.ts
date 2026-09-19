/**
 * Push-to-talk state, as pure transitions. No SDK imports, so every listening
 * transition is testable in Node.
 *
 * The rule the transitions exist to keep: the lens must never sit in
 * `listening` with the microphone shut, and a release must always be able to
 * shut it — including a release that arrives with no audio, a clip too short
 * to be speech, or a failed transcription.
 */

import { MIN_CLIP_MS, pcmDurationMs } from "./audio.ts";
import { COLS, truncate } from "./hud.ts";

export type VoicePhase = "idle" | "listening" | "transcribing" | "result" | "error";

export interface VoiceState {
  readonly phase: VoicePhase;
  /** Bytes of PCM captured for the current, or most recent, clip. */
  readonly captured: number;
  readonly transcript?: string;
  /** What the transcript resolved to, in the wearer's words. */
  readonly outcome?: string;
  readonly message?: string;
}

export const IDLE_VOICE: VoiceState = { phase: "idle", captured: 0 };

/** A long press opens the microphone — unless it is already open. */
export function startListening(state: VoiceState): { state: VoiceState; openMic: boolean } {
  if (state.phase === "listening") return { state, openMic: false };
  return { state: { phase: "listening", captured: 0 }, openMic: true };
}

/** Frames arriving outside a press belong to nothing and are discarded. */
export function captureAudio(state: VoiceState, bytes: number): VoiceState {
  if (state.phase !== "listening") return state;
  return { ...state, captured: state.captured + bytes };
}

/**
 * The release always closes the microphone it opened. It only asks for a
 * transcription when there is enough audio to be worth one.
 */
export function stopListening(state: VoiceState): { state: VoiceState; closeMic: boolean; transcribe: boolean } {
  if (state.phase !== "listening") return { state, closeMic: false, transcribe: false };
  if (state.captured === 0) {
    return { state: { phase: "error", captured: 0, message: "no audio from the glasses mic" }, closeMic: true, transcribe: false };
  }
  if (pcmDurationMs(state.captured) < MIN_CLIP_MS) {
    return { state: { phase: "error", captured: state.captured, message: "too short — hold, then speak" }, closeMic: true, transcribe: false };
  }
  return { state: { phase: "transcribing", captured: state.captured }, closeMic: true, transcribe: true };
}

/**
 * A finished utterance goes to the transcriber while the microphone stays
 * open: continuous capture never stops to think.
 */
export function voiceTranscribing(state: VoiceState): VoiceState {
  return { phase: "transcribing", captured: state.captured };
}

export function voiceResolved(state: VoiceState, transcript: string, outcome: string): VoiceState {
  return { phase: "result", captured: state.captured, transcript, outcome };
}

/** A failure keeps the transcript: a misheard command must stay visible. */
export function voiceFailed(state: VoiceState, message: string): VoiceState {
  return { phase: "error", captured: state.captured, transcript: state.transcript, message };
}

/** The result and error rows are transient; listening is not. */
export function voiceIsTransient(state: VoiceState): boolean {
  return state.phase === "result" || state.phase === "error";
}

/**
 * The on-lens microphone rows: at most two, so the Space list keeps its
 * height. An empty array means the microphone is not in the wearer's way.
 */
export function renderVoiceStatus(state: VoiceState, width: number = COLS): string[] {
  switch (state.phase) {
    case "idle": return [];
    case "listening": return [truncate("[MIC] listening…", width)];
    case "transcribing": return [truncate("[MIC] transcribing…", width)];
    case "error": {
      const failure = `[MIC] ${state.message ?? "failed"}`;
      if (!state.transcript) return [truncate(failure, width)];
      return [truncate(`[MIC] "${state.transcript}"`, width), truncate(`! ${state.message ?? "failed"}`, width)];
    }
    case "result": {
      const heard = `[MIC] "${state.transcript ?? ""}"`;
      const outcome = `→ ${state.outcome ?? ""}`;
      const single = `${heard} ${outcome}`;
      if (single.length <= width) return [single];
      return [truncate(heard, width), truncate(outcome, width)];
    }
  }
}

/** The one-word microphone state for the temporary hardware diagnostic row. */
export function voiceDebugMark(state: VoiceState): string {
  return state.phase;
}
