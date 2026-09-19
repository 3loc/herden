/**
 * Lens attention: when the HUD is lit, and what brings it back.
 *
 * While an Even Hub app is foreground it owns the lens — the system Dashboard
 * and HeadUp do not run — so a HUD that never blanks is a HUD that is lit
 * permanently. This module restores the natural behaviour: the lens goes dark
 * when nothing is happening, and a tilt of the head brings it back.
 *
 * Pure and SDK-free, so every rule is testable in Node. The caller owns the
 * clock, the bridge and the microphone; this module only decides.
 */

import type { Agent, Snapshot } from "./protocol";

// ---------------------------------------------------------------------------
// Calibration. Everything a wearer might have to tune lives in this block.
//
// We have no ground truth for the G2's IMU axes or units: the SDK declares
// `IMU_Report_Data { x, y, z }` as bare doubles with no documented frame, no
// scale and no sign convention. So the axis, the sign and the thresholds are
// constants rather than derived values, and `GESTURE_DEBUG` prints the live
// triple and the computed delta on the lens so real numbers can be read off
// the glasses and pasted back in here.
// ---------------------------------------------------------------------------

/**
 * IMU report pace in milliseconds; the SDK's `ImuReportPace` is the same
 * number on the wire (100…1000, step 100). 300 ms is roughly three samples a
 * second: fast enough that a deliberate head-raise is caught within a blink,
 * slow enough that the event stream stays cheap while the lens is dark.
 */
export const IMU_REPORT_PACE_MS = 300;

/** Which of `x`/`y`/`z` reads as head pitch. Unverified — see above. */
export const PITCH_AXIS: "x" | "y" | "z" = "y";

/** `1` if pitching the head UP makes `PITCH_AXIS` rise; `-1` if it falls. */
export const PITCH_SIGN = 1;

/**
 * Pitch above the resting baseline that counts as "looking up".
 *
 * Measured on Ted's G2 (2026-09-19): the axis reads about -0.14 looking
 * straight ahead and +0.10 or more at the HeadUp position, so the real swing
 * is ~0.24. Fire at roughly two thirds of that, which clears normal head
 * bob while still triggering before the gesture is fully complete.
 */
export const WAKE_PITCH_DELTA = 0.15;

/**
 * The head has to settle back below this before another wake can fire. The
 * gap between the two thresholds is the hysteresis band: without it a head
 * hovering on the threshold would toggle the lens every sample.
 */
export const RELEASE_PITCH_DELTA = 0.07;

/** How fast the resting baseline follows a settled head (EMA weight). */
export const BASELINE_ALPHA = 0.08;

/**
 * Samples to swallow before the first wake can fire, so enabling the IMU
 * while the head is already raised does not read as a gesture.
 */
export const BASELINE_WARMUP_SAMPLES = 4;

/** Idle time with no gesture, no command and no news before the lens blanks. */
export const IDLE_SLEEP_MS = 15_000;

/**
 * Hard cap on one lit session. The microphone is open for the whole of it, so
 * a session that somehow never goes idle must still end by itself rather than
 * stream audio forever.
 */
export const AWAKE_SESSION_MAX_MS = 180_000;

/** How often the caller should ask `dueForSleep`. */
export const ATTENTION_TICK_MS = 1_000;

// ---------------------------------------------------------------------------
// Tilt detection
// ---------------------------------------------------------------------------

export interface ImuSample { x?: number; y?: number; z?: number }

export interface TiltOptions {
  axis: "x" | "y" | "z";
  sign: number;
  wakeDelta: number;
  releaseDelta: number;
  alpha: number;
  warmup: number;
}

export const TILT_DEFAULTS: TiltOptions = {
  axis: PITCH_AXIS, sign: PITCH_SIGN, wakeDelta: WAKE_PITCH_DELTA,
  releaseDelta: RELEASE_PITCH_DELTA, alpha: BASELINE_ALPHA, warmup: BASELINE_WARMUP_SAMPLES,
};

/**
 * Samples the head may sit above the release threshold before the baseline
 * gives up and adopts the current pose as rest.
 *
 * Freezing the baseline while raised stops a held tilt from erasing the
 * gesture, but on real hardware (2026-09-19) it also stranded the wearer: the
 * baseline had settled at an old pose, every later sample read as "still
 * raised", so the detector never re-armed and the dark lens could not be woken
 * by tilting at all. If the head has been "raised" this long, it is not a
 * gesture — it is the new resting position.
 */
export const UNSETTLED_REARM_SAMPLES = 25;

export interface TiltState {
  /** Set once a raise has actually crossed `wakeDelta` on this hardware. */
  readonly proven?: boolean;
  /** Consecutive samples spent above the release threshold. */
  readonly unsettled?: number;
  /** Resting orientation on `axis`; `null` until the first sample seeds it. */
  readonly baseline: number | null;
  /** Latest pitch relative to that baseline, already signed. */
  readonly delta: number;
  /** Whether the head has settled enough that a raise could fire again. */
  readonly armed: boolean;
  readonly samples: number;
  /** The raw triple, kept only so the diagnostic row can show real numbers. */
  readonly last: { x: number; y: number; z: number } | null;
}

export const RESTING_TILT: TiltState = { baseline: null, delta: 0, armed: false, samples: 0, last: null };

function finite(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/**
 * Fold one IMU report into the tilt state.
 *
 * The baseline is an exponential average of the *settled* head only: while the
 * head is raised past the release threshold it is frozen, so holding a tilt
 * never turns that tilt into the new resting orientation (which would make the
 * wake gesture disappear after a few seconds of reading).
 */
export function observeTilt(
  state: TiltState,
  sample: ImuSample,
  options: Partial<TiltOptions> = {},
): { state: TiltState; wake: boolean } {
  const { axis, sign, wakeDelta, releaseDelta, alpha, warmup } = { ...TILT_DEFAULTS, ...options };
  const last = { x: finite(sample.x), y: finite(sample.y), z: finite(sample.z) };
  const value = last[axis];
  const samples = state.samples + 1;
  if (state.baseline === null) {
    return { state: { baseline: value, delta: 0, armed: false, samples, last, proven: state.proven }, wake: false };
  }
  const delta = (value - state.baseline) * sign;
  const settled = delta <= releaseDelta;
  const unsettled = settled ? 0 : (state.unsettled ?? 0) + 1;
  if (unsettled >= UNSETTLED_REARM_SAMPLES) {
    // Adopt this pose as rest and re-arm, so a stale baseline self-heals.
    return {
      state: { baseline: value, delta: 0, armed: true, samples, last, proven: state.proven, unsettled: 0 },
      wake: false,
    };
  }
  // Arming is the low half of the hysteresis band; firing is the high half.
  let armed = state.armed || settled;
  const wake = armed && samples > warmup && delta >= wakeDelta;
  if (wake) armed = false;
  const baseline = settled ? state.baseline + alpha * (value - state.baseline) : state.baseline;
  return { state: { baseline, delta, armed, samples, last, proven: state.proven || wake, unsettled }, wake };
}

/** The IMU half of the diagnostic row: the raw triple and the pitch delta. */
export function renderTiltDebug(state: TiltState): string {
  if (!state.last) return "imu=none";
  const fixed = (value: number): string => value.toFixed(2);
  const delta = `${state.delta >= 0 ? "+" : ""}${fixed(state.delta)}`;
  return `imu=${fixed(state.last.x)},${fixed(state.last.y)},${fixed(state.last.z)} d=${delta}`;
}

// ---------------------------------------------------------------------------
// Sleep/wake state machine
// ---------------------------------------------------------------------------

export type AttentionPhase = "awake" | "asleep";

/** Why the lens went dark; only ever shown in diagnostics. */
export type SleepReason = "idle" | "session-cap";

export interface AttentionState {
  readonly phase: AttentionPhase;
  /** When the current phase began. */
  readonly since: number;
  /** Last gesture, command or attention-worthy change, while awake. */
  readonly activity: number;
}

export function initialAttention(now: number): AttentionState {
  return { phase: "awake", since: now, activity: now };
}

/** Anything the wearer did, or anything worth their attention, defers sleep. */
export function noteActivity(state: AttentionState, now: number): AttentionState {
  if (state.phase !== "awake") return state;
  return { ...state, activity: now };
}

export function wakeAttention(state: AttentionState, now: number): { state: AttentionState; changed: boolean } {
  if (state.phase === "awake") return { state: noteActivity(state, now), changed: false };
  return { state: { phase: "awake", since: now, activity: now }, changed: true };
}

export function sleepAttention(state: AttentionState, now: number): { state: AttentionState; changed: boolean } {
  if (state.phase === "asleep") return { state, changed: false };
  return { state: { phase: "asleep", since: now, activity: state.activity }, changed: true };
}

/**
 * The only two ways a lit lens ends on its own: nothing happened for a while,
 * or the session as a whole ran too long. The cap is checked first, so a
 * wearer who keeps a session busy forever still gets the microphone shut.
 */
export function dueForSleep(
  state: AttentionState,
  now: number,
  idleMs: number = IDLE_SLEEP_MS,
  sessionMs: number = AWAKE_SESSION_MAX_MS,
  canWake: boolean = true,
): SleepReason | null {
  if (state.phase !== "awake") return null;
  // Never take away the lens until something is known to bring it back. The
  // tilt thresholds are guesses until calibrated on real hardware, and a dark
  // lens that cannot wake itself is indistinguishable from a dead app.
  if (!canWake) return null;
  if (now - state.since >= sessionMs) return "session-cap";
  if (now - state.activity >= idleMs) return "idle";
  return null;
}

/**
 * Whether the tilt gesture has been *observed* to cross the wake threshold at
 * least once. Until it has, idle sleep stays disabled: long press is then the
 * only way back, and requiring a gesture to undo an automatic action is the
 * kind of trap that reads as a broken app.
 */
export function wakeProven(state: TiltState): boolean {
  return state.proven === true;
}

/** Statuses that are waiting on the wearer rather than on a machine. */
const WORTH_WAKING: ReadonlySet<Agent["status"]> = new Set<Agent["status"]>(["blocked", "failed", "done"]);

/**
 * Whether a fresh snapshot is worth keeping the lens lit for. A Space that
 * starts or stops working is churn; a Space that starts waiting on the wearer,
 * or a roster that gained or lost a Space, is news.
 */
export function attentionWorthy(previous: Snapshot | null, next: Snapshot | null): boolean {
  if (!next) return false;
  if (!previous) return next.agents.length > 0;
  const before = new Map(previous.agents.map((agent) => [agent.id, agent.status]));
  if (before.size !== next.agents.length) return true;
  return next.agents.some((agent) => {
    const was = before.get(agent.id);
    if (was === undefined) return true;
    return was !== agent.status && WORTH_WAKING.has(agent.status);
  });
}
