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
// The SDK supplies raw IMU triples, not a firmware head-up event or a
// calibrated pitch angle. These values are relative movement margins measured
// on the worn G2, not absolute orientations or universal device constants.
// ---------------------------------------------------------------------------

/**
 * IMU report pace in milliseconds; the SDK's `ImuReportPace` is the same
 * number on the wire (100…1000, step 100). At 300 ms a short head raise can
 * fall between reports. IMU samples do not repaint, so use the 100 ms pace.
 */
export const IMU_REPORT_PACE_MS = 100;

/** Worn-G2 calibration: X, not Y, moves strongly with head pitch. */
export const PITCH_AXIS: "x" | "y" | "z" = "x";

/** `1` if pitching the head UP makes `PITCH_AXIS` rise; `-1` if it falls. */
export const PITCH_SIGN = 1;

/**
 * The marked 20 September calibration moved X from roughly 0.01 to +0.35
 * when looking up. Level right/left turns kept X within about -0.12..+0.02.
 * The margin is relative because resting X changes with posture and wear.
 */
export const WAKE_PITCH_DELTA = 0.18;

/** Hysteresis below the wake rise, allowing a new movement after settling. */
export const RELEASE_PITCH_DELTA = 0.08;

/** How fast the resting baseline follows a settled head (EMA weight). */
export const BASELINE_ALPHA = 0.08;

/** Follow a lower pose promptly, but not a single downward sensor spike. */
export const DARK_LOWER_ALPHA = 0.25;

/** Follow slow upward posture drift without erasing a deliberate head raise. */
export const DARK_DRIFT_ALPHA = 0.005;

/** A held raised pose becomes the new rest instead of stranding the detector. */
export const UNSETTLED_REARM_SAMPLES = 75;

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

export interface TiltState {
  /** Set once a level-to-head-up transition has been observed. */
  readonly proven?: boolean;
  /** Samples spent above the release band before adopting a new rest pose. */
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
 * Fold one valid IMU report into a relative head-up detector. An absolute Y
 * threshold left the lens permanently dark when the worn resting pose moved.
 */
export function observeTilt(
  state: TiltState,
  sample: ImuSample,
  options: Partial<TiltOptions> = {},
): { state: TiltState; wake: boolean } {
  const { axis, sign, wakeDelta, releaseDelta, alpha, warmup } = { ...TILT_DEFAULTS, ...options };
  const axisValue = sample[axis];
  if (typeof axisValue !== "number" || !Number.isFinite(axisValue)) {
    return { state, wake: false };
  }
  const last = { x: finite(sample.x), y: finite(sample.y), z: finite(sample.z) };
  const value = last[axis];
  const samples = state.samples + 1;
  if (state.baseline === null) {
    return { state: { baseline: value, delta: 0, armed: false, samples, last, proven: state.proven, unsettled: 0 }, wake: false };
  }
  const delta = (value - state.baseline) * sign;
  const settled = delta <= releaseDelta;
  const unsettled = settled ? 0 : (state.unsettled ?? 0) + 1;
  if (unsettled >= UNSETTLED_REARM_SAMPLES) {
    return {
      state: { baseline: value, delta: 0, armed: true, samples, last, proven: state.proven, unsettled: 0 },
      wake: false,
    };
  }
  let armed = state.armed || settled;
  const wake = armed && samples > warmup && delta >= wakeDelta;
  if (wake) armed = false;
  const baseline = settled ? state.baseline + alpha * (value - state.baseline) : state.baseline;
  return { state: { baseline, delta, armed, samples, last, proven: state.proven || wake, unsettled }, wake };
}

/**
 * Re-anchor at the pose that actually closed the lens. A held pose has zero
 * relative rise and cannot relight it on the next IMU sample.
 */
export function prepareTiltForSleep(state: TiltState): TiltState {
  if (!state.last) return { ...RESTING_TILT, proven: state.proven };
  return {
    ...state,
    baseline: state.last[PITCH_AXIS],
    delta: 0,
    armed: true,
    unsettled: 0,
    samples: Math.max(state.samples, BASELINE_WARMUP_SAMPLES + 1),
  };
}

/**
 * While dark, a held lower pose becomes rest; a rising movement is measured
 * from that rest rather than from a hard-coded Y level. A small amount of
 * upward drift tracking prevents long-term posture changes from self-waking.
 */
export function observeSleepingTilt(state: TiltState, sample: ImuSample): { state: TiltState; wake: boolean } {
  const axisValue = sample[PITCH_AXIS];
  if (typeof axisValue !== "number" || !Number.isFinite(axisValue)) return { state, wake: false };
  const observed = observeTilt(state, sample);
  if (observed.wake || !observed.state.last || state.baseline === null) return observed;
  // A raised pose held for the re-arm interval has just become the new rest.
  // Do not restore the previous baseline on that same sample.
  if ((state.unsettled ?? 0) >= UNSETTLED_REARM_SAMPLES - 1
    && observed.state.unsettled === 0) return observed;
  const value = observed.state.last[PITCH_AXIS];
  const rise = (value - state.baseline) * PITCH_SIGN;
  if (rise < 0) {
    const baseline = state.baseline + DARK_LOWER_ALPHA * (value - state.baseline);
    return { wake: false, state: { ...observed.state, baseline, delta: (value - baseline) * PITCH_SIGN } };
  }
  if (rise <= RELEASE_PITCH_DELTA) {
    const baseline = state.baseline + DARK_DRIFT_ALPHA * (value - state.baseline);
    return { wake: false, state: { ...observed.state, baseline, delta: (value - baseline) * PITCH_SIGN } };
  }
  // Keep the lower reference during a real rise so a slow gesture accumulates.
  return { wake: false, state: { ...observed.state, baseline: state.baseline } };
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

/** The normal HUD boot state: dark until a deliberate head-up tilt. */
export function initialSleepingAttention(now: number): AttentionState {
  return { phase: "asleep", since: now, activity: now };
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

/** Active speech and queued transcription defer idle sleep, never the cap. */
export function deferIdleSleep(reason: SleepReason | null, voiceBusy: boolean): SleepReason | null {
  return reason === "idle" && voiceBusy ? null : reason;
}

/**
 * Whether a deliberate tilt has been observed at least once. Until then,
 * automatic idle sleep stays disabled so an uncalibrated detector cannot
 * strand the wearer behind a dark lens.
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
