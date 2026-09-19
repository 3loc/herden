import assert from "node:assert/strict";
import { test } from "node:test";
import {
  AWAKE_SESSION_MAX_MS, IDLE_SLEEP_MS, IMU_REPORT_PACE_MS, PITCH_AXIS, RELEASE_PITCH_DELTA,
  RESTING_TILT, UNSETTLED_REARM_SAMPLES, WAKE_PITCH_DELTA, attentionWorthy, dueForSleep, initialAttention, noteActivity,
  observeTilt, renderTiltDebug, sleepAttention, wakeAttention,
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
// Pitch against a rolling baseline
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

test("the first sample only seeds the baseline: no phantom wake at startup", () => {
  // Enabling the IMU with the head already raised must not read as a gesture.
  const { wakes } = pitches([5, 5, 5, 5, 5, 5, 5, 5]);
  assert.deepEqual(wakes, []);
  const seeded = observeTilt(RESTING_TILT, axis(5));
  assert.equal(seeded.state.baseline, 5);
  assert.equal(seeded.state.delta, 0);
});

test("a raise past the threshold wakes once, not once per sample", () => {
  const raised = WAKE_PITCH_DELTA * 2;
  const { wakes } = pitches([0, 0, 0, 0, 0, 0, raised, raised, raised, raised]);
  assert.deepEqual(wakes, [6]);
});

test("hysteresis: the head must settle below the release band to wake again", () => {
  const raised = WAKE_PITCH_DELTA + 0.05;
  // Hovering between the two thresholds cannot re-arm, so it cannot flap.
  const hover = (RELEASE_PITCH_DELTA + WAKE_PITCH_DELTA) / 2;
  const flap = [0, 0, 0, 0, 0, 0, raised, hover, raised, hover, raised, hover, raised];
  assert.deepEqual(pitches(flap).wakes, [6]);
  // Dropping back under the release threshold re-arms it.
  const settle = [0, 0, 0, 0, 0, 0, raised, 0, raised];
  assert.deepEqual(pitches(settle).wakes, [6, 8]);
});

test("a brief hold keeps the gesture; a long one becomes the new rest", () => {
  const raised = WAKE_PITCH_DELTA * 3;
  // A few seconds of reading with the head up: the baseline must not move,
  // or looking back down and up again would stop waking the lens.
  const brief = [...Array.from({ length: 6 }, () => 0), ...Array.from({ length: 10 }, () => raised)];
  const held = pitches(brief);
  assert.deepEqual(held.wakes, [6]);
  assert.ok(Math.abs(held.state.baseline ?? 99) < RELEASE_PITCH_DELTA, String(held.state.baseline));
  assert.deepEqual(pitches([0, raised], held.state).wakes, [1]);

  // Sitting "raised" indefinitely is not a gesture, it is a new posture. The
  // baseline has to adopt it, or a stale baseline strands the wearer with a
  // dark lens that no tilt can wake — observed on hardware 2026-09-19.
  const forever = [...Array.from({ length: 6 }, () => 0), ...Array.from({ length: 100 }, () => raised)];
  const settled = pitches(forever);
  assert.deepEqual(settled.wakes, [6]);
  assert.ok(Math.abs(settled.state.delta) < RELEASE_PITCH_DELTA, String(settled.state.delta));
  assert.equal(settled.state.armed, true);
  assert.deepEqual(pitches([raised * 2], settled.state).wakes, [0]);
});

test("the baseline follows a slow drift, which therefore never wakes the lens", () => {
  // A head settling over a minute: each step is far below the wake threshold.
  const drift = Array.from({ length: 200 }, (_, index) => index * (WAKE_PITCH_DELTA / 40));
  const { state, wakes } = pitches(drift);
  assert.deepEqual(wakes, []);
  assert.ok((state.baseline ?? 0) > WAKE_PITCH_DELTA, String(state.baseline));
});

test("a missing or non-finite IMU field reads as zero rather than NaN", () => {
  const observed = observeTilt({ ...RESTING_TILT, baseline: 0, samples: 10, armed: true }, { x: Number.NaN });
  assert.equal(observed.state.delta, 0);
  assert.deepEqual(observed.state.last, { x: 0, y: 0, z: 0 });
  assert.equal(observed.wake, false);
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

test("a stale baseline self-heals instead of stranding the wearer", () => {
  let tilt = RESTING_TILT;
  // Baseline settles low, then the head sits raised for good: the old
  // behaviour froze the baseline and could never re-arm.
  for (let i = 0; i < 5; i++) tilt = observeTilt(tilt, { y: -0.14 }).state;
  for (let i = 0; i < UNSETTLED_REARM_SAMPLES + 1; i++) tilt = observeTilt(tilt, { y: 0.12 }).state;
  assert.equal(tilt.armed, true, "re-armed once the pose is clearly the new rest");
  assert.ok(Math.abs(tilt.delta) < 0.05, "the raised pose became the baseline");
  // And a genuine raise from there still wakes.
  const raised = observeTilt(tilt, { y: 0.4 });
  assert.equal(raised.wake, true);
});
