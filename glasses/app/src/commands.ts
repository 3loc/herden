/**
 * Spoken command grammar. Pure and SDK-free, so the whole vocabulary is
 * testable in Node.
 *
 * Transcripts arrive from a speech model, so they carry casing, punctuation,
 * filler and English number words that the wearer never meant as content.
 */

export type VoiceCommand =
  /** `position` is the 1-based row number as rendered on the lens. */
  | { type: "open"; position: number }
  | { type: "back" }
  /** Blank the lens and shut the microphone; the spoken twin of a long press. */
  | { type: "sleep" }
  | { type: "dictate"; text: string }
  | { type: "unknown"; transcript: string };

const NUMBER_WORDS: Record<string, number> = {
  one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16,
  seventeen: 17, eighteen: 18, nineteen: 19, twenty: 20,
};

/**
 * Homophones a speech model reaches for instead of a digit. They only count
 * after an explicit `open`, where nothing else could be meant.
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

/** `dictate` keeps its text verbatim; everything else is normalised away. */
const DICTATE = /^\s*(?:please\s+|hey\s+|ok(?:ay)?\s+|herden[\s,]+)*(?:dictate|dictation|type|say)\b[\s,:-]*(.*)$/i;

export function parseCommand(transcript: string): VoiceCommand {
  const raw = transcript.trim();
  const dictated = DICTATE.exec(raw);
  if (dictated) {
    const text = (dictated[1] ?? "").trim();
    if (text.length > 0) return { type: "dictate", text };
  }

  const tokens = words(raw).filter((word) => !FILLER.has(word));
  if (tokens.length === 0) return { type: "unknown", transcript: raw };

  const [first, second, third] = tokens;
  if (tokens.length <= 2 && (first === "back" || first === "close" || (first === "go" && second === "back"))) {
    return { type: "back" };
  }
  // "sleep", "go to sleep", "stop", "stop listening": end the lit session.
  if (tokens.length <= 3 && tokens[tokens.length - 1] === "sleep") return { type: "sleep" };
  if (first === "stop" && (tokens.length === 1 || second === "listening" || second === "listen")) {
    return { type: "sleep" };
  }
  if (first === "open") {
    const rest = second === "space" || second === "row" || second === "number" ? third : second;
    const position = numberFrom(rest, true);
    if (position !== null && tokens.length <= 3) return { type: "open", position };
  }
  if (tokens.length === 1) {
    const position = numberFrom(first, false);
    if (position !== null) return { type: "open", position };
  }
  if (first === "space" && tokens.length === 2) {
    const position = numberFrom(second, true);
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
    case "open": return `open ${command.position}`;
    case "back": return "back";
    case "sleep": return "sleep";
    // The HUD endpoint is read-only by design: `controls_allowed` is false and
    // no Host write path exists yet. Say so, with the text that was heard.
    case "dictate": return `dictation needs Host support: "${command.text}"`;
    case "unknown": return "not a command";
  }
}
