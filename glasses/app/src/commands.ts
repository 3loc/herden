/**
 * Spoken command grammar. Pure and SDK-free, so the whole vocabulary is
 * testable in Node.
 *
 * Transcripts arrive from a speech model, so they carry casing, punctuation,
 * filler and English number words that the wearer never meant as content.
 */

import type { Command } from "./protocol.ts";

export type VoiceCommand =
  /** `position` is the 1-based row number as rendered on the lens. */
  | { type: "open"; position: number }
  | { type: "back" }
  | { type: "page"; direction: "up" | "down" }
  | { type: "close" }
  | { type: "dictate"; text: string }
  | { type: "unknown"; transcript: string };

const NUMBER_WORDS: Record<string, number> = {
  one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16,
  seventeen: 17, eighteen: 18, nineteen: 19, twenty: 20,
};

/**
 * Homophones a speech model reaches for instead of a digit. They only count
 * after an explicit row-navigation verb, where nothing else could be meant.
 */
const SPOKEN_HOMOPHONES: Record<string, number> = { won: 1, to: 2, too: 2, for: 4, ate: 8 };

/** Words that carry no instruction; dropped before the grammar is matched. */
const FILLER = new Set(["um", "uh", "erm", "er", "ah", "hmm", "please", "just", "ok", "okay", "hey", "now", "the", "a", "herden"]);

function words(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .split(/\s+/)
    .filter((word) => word.length > 0);
}

function numberFrom(word: string | undefined, allowHomophones: boolean): number | null {
  if (!word) return null;
  if (/^\d{1,3}$/.test(word)) {
    const digits = Number(word);
    return digits >= 1 ? digits : null;
  }
  const spoken = NUMBER_WORDS[word] ?? (allowHomophones ? SPOKEN_HOMOPHONES[word] : undefined);
  return spoken ?? null;
}

export function parseCommand(transcript: string): VoiceCommand {
  const raw = transcript.trim();
  // Dictation must retain the original words, punctuation and Unicode. The
  // navigation tokenizer below intentionally drops filler, which would mangle
  // user-authored text such as "the" or "please".
  const dictated = raw.match(/^(?:(?:please|okay|ok|hey)\s+)*dictate(?:\s+|[:,]\s*)([\s\S]+)$/iu);
  if (dictated?.[1]?.trim()) return { type: "dictate", text: dictated[1].trim() };
  const tokens = words(raw).filter((word) => !FILLER.has(word));
  if (tokens.length === 0) return { type: "unknown", transcript: raw };

  const [first, second] = tokens;
  if (tokens.length === 1 && first === "close") return { type: "close" };
  if (tokens.length === 2 && first === "go" && second === "back") return { type: "back" };
  if (tokens.length === 2 && first === "page" && (second === "up" || second === "down")) {
    return { type: "page", direction: second };
  }
  if (tokens.length === 2 && first === "open") {
    const position = numberFrom(second, true);
    if (position !== null) return { type: "open", position };
  }
  if (tokens.length === 3 && first === "go" && second === "to") {
    const position = numberFrom(tokens[2], true);
    if (position !== null) return { type: "open", position };
  }
  return { type: "unknown", transcript: raw };
}

/**
 * One lens-sized phrase for what a transcript resolved to, so a misheard
 * command is visible rather than silent.
 */
export function describeCommand(command: VoiceCommand): string {
  switch (command.type) {
    case "open": return `Go to ${command.position}`;
    case "back": return "Go back";
    case "page": return `Page ${command.direction}`;
    case "close": return "Close";
    case "dictate": return `Dictate: ${command.text}`;
    case "unknown": return "not a command";
  }
}

/** End-of-phrase dictation types and presses Return in one Host operation. */
export function dictationSubmission(agentId: string, text: string): Command {
  return { action: "send_text", agentId, text, submit: true };
}
