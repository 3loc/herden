import assert from "node:assert/strict";
import { test } from "node:test";
import {
  AWAKE_SESSION_MAX_MS, IDLE_SLEEP_MS, IMU_REPORT_PACE_MS, PITCH_AXIS, RELEASE_PITCH_DELTA,
  RESTING_TILT, WAKE_PITCH_DELTA, attentionWorthy, deferIdleSleep, dueForSleep,
  initialAttention, initialSleepingAttention, noteActivity,
  observeSleepingTilt, observeTilt, prepareTiltForSleep, renderTiltDebug,
  sleepAttention, wakeAttention,
} from "../src/attention.ts";
import type { ImuSample, TiltState } from "../src/attention.ts";
import { COLS, renderGestureDebug } from "../src/hud.ts";
import type { Agent, Snapshot } from "../src/protocol.ts";

// ---------------------------------------------------------------------------
// Sleep/wake state machine
// ---------------------------------------------------------------------------

test("a lit lens blanks after the idle period and not a tick before", () => {
  const start = initialAttention(1_000);
  assert.equal(start.phase, "awake");
  assert.equal(dueForSleep(start, 1_000 + IDLE_SLEEP_MS - 1), null);
  assert.equal(dueForSleep(start, 1_000 + IDLE_SLEEP_MS), "idle");
});

test("the HUD boots dark until a deliberate wake", () => {
  const dark = initialSleepingAttention(100);
  assert.equal(dark.phase, "asleep");
  assert.equal(wakeAttention(dark, 200).state.phase, "awake");
});

test("active voice defers idle sleep but never the three-minute safety cap", () => {
  const awake = initialAttention(0);
  assert.equal(deferIdleSleep(dueForSleep(awake, IDLE_SLEEP_MS), true), null);
  assert.equal(deferIdleSleep(dueForSleep(awake, AWAKE_SESSION_MAX_MS), true), "session-cap");
});

test("a gesture, a command or news defers sleep by the whole idle period", () => {
  let attention = initialAttention(0);
  attention = noteActivity(attention, IDLE_SLEEP_MS - 1);
  assert.equal(dueForSleep(attention, IDLE_SLEEP_MS + 1), null);
  assert.equal(dueForSleep(attention, IDLE_SLEEP_MS - 1 + IDLE_SLEEP_MS), "idle");
});

test("the session cap sleeps a lens that never goes idle", () => {
  let attention = initialAttention(0);
  // Busy every second for ten minutes: idle never fires, the cap must.
  for (let now = 0; now < AWAKE_SESSION_MAX_MS; now += 1_000) attention = noteActivity(attention, now);
  assert.equal(dueForSleep(attention, AWAKE_SESSION_MAX_MS - 1), null);
  assert.equal(dueForSleep(attention, AWAKE_SESSION_MAX_MS), "session-cap");
  // The cap outranks idle when both are due.
  const stale = initialAttention(0);
  assert.equal(dueForSleep(stale, AWAKE_SESSION_MAX_MS + 1), "session-cap");
});

test("an asleep lens is never due for sleep and cannot be woken by activity", () => {
  const { state: asleep, changed } = sleepAttention(initialAttention(0), 5_000);
  assert.ok(changed);
  assert.equal(asleep.phase, "asleep");
  assert.equal(dueForSleep(asleep, 10_000_000), null);
  assert.equal(noteActivity(asleep, 6_000).phase, "asleep");
  assert.equal(sleepAttention(asleep, 7_000).changed, false);
});

test("waking restarts both clocks, and waking an awake lens is only activity", () => {
  const { state: asleep } = sleepAttention(initialAttention(0), 5_000);
  const woken = wakeAttention(asleep, 100_000);
  assert.ok(woken.changed);
  assert.deepEqual(woken.state, { phase: "awake", since: 100_000, activity: 100_000 });
  assert.equal(dueForSleep(woken.state, 100_000 + IDLE_SLEEP_MS - 1), null);
  // Already awake: no redraw, no new session, just a deferred sleep.
  const again = wakeAttention(woken.state, 110_000);
  assert.equal(again.changed, false);
  assert.equal(again.state.since, 100_000);
  assert.equal(again.state.activity, 110_000);
});

// ---------------------------------------------------------------------------
// Relative head-up movement and dark-state re-basing
// ---------------------------------------------------------------------------

const axis = (value: number): ImuSample => ({ x: 0, y: 0, z: 0, [PITCH_AXIS]: value });

/** Feed samples and report every wake that fired. */
function pitches(values: number[], from: TiltState = RESTING_TILT): { state: TiltState; wakes: number[] } {
  let state = from;
  const wakes: number[] = [];
  values.forEach((value, index) => {
    const observed = observeTilt(state, axis(value));
    state = observed.state;
    if (observed.wake) wakes.push(index);
  });
  return { state, wakes };
}

test("starting head-up seeds the baseline without an immediate wake", () => {
  const { wakes } = pitches([0.1, 0.1, 0.1, 0.1, 0.1, 0.1]);
  assert.deepEqual(wakes, []);
  const seeded = observeTilt(RESTING_TILT, axis(0.1));
  assert.equal(seeded.state.baseline, 0.1);
  assert.equal(seeded.state.delta, 0);
});

test("measured level-to-head-up movement wakes exactly once", () => {
  const { wakes } = pitches([-0.14, -0.13, -0.12, -0.11, -0.1, 0, 0.1, 0.12, 0.1]);
  assert.deepEqual(wakes, [6]);
  assert.ok(0 < RELEASE_PITCH_DELTA && RELEASE_PITCH_DELTA < WAKE_PITCH_DELTA);
});

test("ordinary movement below the measured rise does not wake", () => {
  const rest = pitches(Array.from({ length: 6 }, () => 0.03)).state;
  let dark = prepareTiltForSleep(rest);
  for (const value of [0.07, 0.10, 0.12, 0.08, 0.03]) {
    const observed = observeSleepingTilt(dark, axis(value));
    assert.equal(observed.wake, false, `X=${value}`);
    dark = observed.state;
  }
  assert.equal(observeSleepingTilt(dark, axis(0.24)).wake, true);
});

test("sleep at a raised pose stays dark until a new relative head-up", () => {
  const first = pitches([-0.14, -0.14, -0.14, -0.14, -0.14, 0.1]);
  assert.deepEqual(first.wakes, [5]);
  const sleeping = prepareTiltForSleep(first.state);
  assert.equal(sleeping.armed, true);
  assert.equal(sleeping.delta, 0);
  assert.equal(observeSleepingTilt(sleeping, axis(0.1)).wake, false);
  let dark = sleeping;
  for (let i = 0; i < 12; i += 1) dark = observeSleepingTilt(dark, axis(0.03)).state;
  assert.equal(observeSleepingTilt(dark, axis(0.24)).wake, true);
});

test("a slow head raise still wakes, without baseline timing effects", () => {
  let state: TiltState = { ...RESTING_TILT, baseline: -0.1, armed: true, samples: 5, last: axis(-0.1) };
  const wakes: number[] = [];
  for (let step = -9; step <= 10; step += 1) {
    const observed = observeSleepingTilt(state, axis(step * 0.01));
    state = observed.state;
    if (observed.wake) wakes.push(step);
  }
  assert.deepEqual(wakes, [9]);
  assert.equal(IMU_REPORT_PACE_MS, 100);
});

test("a held raised pose eventually becomes rest without repeated wake", () => {
  const held = pitches([...Array.from({ length: 5 }, () => -0.1), ...Array.from({ length: 100 }, () => 0.1)]);
  assert.deepEqual(held.wakes, [5]);
  assert.equal(held.state.baseline, 0.1);
  assert.equal(observeSleepingTilt(prepareTiltForSleep(held.state), axis(0.1)).wake, false);
});

test("one downward IMU spike cannot re-base the dark detector enough to false-wake", () => {
  const rest = prepareTiltForSleep(pitches(Array.from({ length: 6 }, () => 0.03)).state);
  const spike = observeSleepingTilt(rest, axis(-0.4));
  assert.equal(spike.wake, false);
  assert.equal(observeSleepingTilt(spike.state, axis(0.03)).wake, false);
});

test("a missing or non-finite pitch report cannot count towards wake", () => {
  const resting = { ...RESTING_TILT, baseline: -0.14, samples: 10, armed: true };
  const observed = observeTilt(resting, { x: Number.NaN });
  assert.equal(observed.state.delta, 0);
  assert.equal(observed.state.last, null);
  assert.equal(observed.wake, false);
  assert.equal(observeTilt(resting, { x: Number.NaN }).wake, false);
  const dark = prepareTiltForSleep(pitches(Array.from({ length: 6 }, () => 0.03)).state);
  assert.deepEqual(observeSleepingTilt(dark, { x: Number.NaN }), { state: dark, wake: false });
});

test("the diagnostic row carries the live triple and the pitch delta", () => {
  assert.equal(renderTiltDebug(RESTING_TILT), "imu=none");
  const state = observeTilt(observeTilt(RESTING_TILT, axis(-0.98)).state, axis(-0.67)).state;
  assert.match(renderTiltDebug(state), /^imu=-?\d+\.\d\d,-?\d+\.\d\d,-?\d+\.\d\d d=\+0\.31$/);
  // It has to survive beside the rest of the diagnostic row.
  const row = renderGestureDebug({ count: 7, field: "sysEvent", eventType: 9, imu: renderTiltDebug(state), mic: "listening" });
  assert.ok(row.includes("imu="), row);
  assert.ok(row.includes(" d="), row);
  assert.ok(row.length <= COLS, `${row.length}: ${row}`);
  // The pace is a single named constant, valid as an SDK ImuReportPace.
  assert.equal(IMU_REPORT_PACE_MS % 100, 0);
  assert.ok(IMU_REPORT_PACE_MS >= 100 && IMU_REPORT_PACE_MS <= 1_000);
});

// ---------------------------------------------------------------------------
// What counts as news
// ---------------------------------------------------------------------------

const agent = (over: Partial<Agent> = {}): Agent =>
  ({ id: "w1:pT", name: "auth", space: "herden", status: "idle", pinned: false, ...over });
const snapshot = (agents: Agent[]): Snapshot => ({
  protocol_version: 1, type: "snapshot", revision: 1, at: 0, inventory_valid: true,
  stale: false, controls_allowed: false, agents, wake: [], summary: "",
});

test("only a change that wants the wearer keeps the lens lit", () => {
  const idle = snapshot([agent({ id: "a" }), agent({ id: "b" })]);
  assert.equal(attentionWorthy(idle, idle), false);
  // Churn: a Space starts working. Nobody is waiting on the wearer.
  assert.equal(attentionWorthy(idle, snapshot([agent({ id: "a", status: "working" }), agent({ id: "b" })])), false);
  // News: a Space starts waiting on the wearer, fails, or finishes.
  for (const status of ["blocked", "failed", "done"] as const) {
    assert.equal(attentionWorthy(idle, snapshot([agent({ id: "a", status }), agent({ id: "b" })])), true, status);
  }
  // News: the roster itself changed.
  assert.equal(attentionWorthy(idle, snapshot([agent({ id: "a" })])), true);
  assert.equal(attentionWorthy(idle, snapshot([agent({ id: "a" }), agent({ id: "b" }), agent({ id: "c" })])), true);
  assert.equal(attentionWorthy(idle, snapshot([agent({ id: "a" }), agent({ id: "z" })])), true);
  // Nothing at all is never news; a first snapshot with Spaces is.
  assert.equal(attentionWorthy(idle, null), false);
  assert.equal(attentionWorthy(null, snapshot([])), false);
  assert.equal(attentionWorthy(null, idle), true);
});

test("captured +0.03 resting pose can re-wake without crossing an absolute negative gate", () => {
  let dark = prepareTiltForSleep(pitches(Array.from({ length: 6 }, () => 0.03)).state);
  for (let i = 0; i < 60; i += 1) {
    const observed = observeSleepingTilt(dark, axis(0.03 + (i % 3) * 0.005));
    assert.equal(observed.wake, false);
    dark = observed.state;
  }
  assert.equal(dark.armed, true);
  assert.equal(observeSleepingTilt(dark, axis(0.24)).wake, true);
});

test("marked worn-G2 samples select X for up, not level right/left turns", () => {
  assert.equal(PITCH_AXIS, "x");
  let dark = prepareTiltForSleep(pitches(Array.from({ length: 6 }, () => 0.005)).state);
  // Rounded from the 20 September trace, at 100 ms IMU pace.
  for (const sample of [
    { x: -0.0348, y: -0.0419, z: 1.0006 },
    { x: -0.0213, y: -0.0736, z: 1.0109 },
    { x: -0.0299, y: -0.0674, z: 0.9963 },
    { x: -0.0224, y: -0.0544, z: 0.9937 },
    { x: -0.0237, y: -0.0474, z: 1.0008 },
    { x: -0.0451, y: -0.0472, z: 1.0033 },
  ]) {
    const observed = observeSleepingTilt(dark, sample);
    assert.equal(observed.wake, false);
    dark = observed.state;
  }
  // Actual look-up transition: X rises across the threshold while Y falls.
  const lookUp = [
    { x: 0.0019, y: -0.0216, z: 0.9936 },
    { x: 0.0461, y: -0.0432, z: 0.9977 },
    { x: 0.1107, y: -0.0536, z: 0.9833 },
    { x: 0.1551, y: -0.0583, z: 0.9892 },
    { x: 0.1994, y: -0.0651, z: 0.9629 },
    { x: 0.2392, y: -0.0636, z: 0.9724 },
    { x: 0.2767, y: -0.0736, z: 0.967 },
    { x: 0.3513, y: -0.0761, z: 0.9317 },
  ];
  const wakes = lookUp.map((sample) => {
    const observed = observeSleepingTilt(dark, sample);
    dark = observed.state;
    return observed.wake;
  });
  assert.equal(wakes.filter(Boolean).length, 1);
  assert.ok(wakes.findIndex(Boolean) >= 4 && wakes.findIndex(Boolean) <= 6);
});

test("marked look-down pose points opposite the X wake direction", () => {
  let dark = prepareTiltForSleep(pitches(Array.from({ length: 6 }, () => -0.05)).state);
  for (const sample of [
    { x: -0.8324, y: 0.1306, z: 0.5443 },
    { x: -0.8046, y: 0.1219, z: 0.5805 },
    { x: -0.8065, y: 0.1133, z: 0.5845 },
  ]) {
    const observed = observeSleepingTilt(dark, sample);
    assert.equal(observed.wake, false);
    dark = observed.state;
  }
});
