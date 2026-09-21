import assert from "node:assert/strict";
import { test } from "node:test";
import { HardwareTrace } from "../src/hardware-trace.ts";

test("hardware trace preserves ordered IMU samples and does not post PCM", async () => {
  const bodies: string[] = [];
  const trace = new HardwareTrace({ endpoint: "/debug", session: "cal", now: () => 123,
    post: async (_url, body) => { bodies.push(body); },
  });
  trace.record("imu", 0.01, 0.02, 1.0, false);
  trace.record("hub", 4);
  trace.audioFrame(640);
  trace.audioFrame(640);
  trace.audioSummary();
  await trace.flush();
  const events = bodies.flatMap((body) => JSON.parse(body).events);
  assert.deepEqual(events, [[123, "imu", 0.01, 0.02, 1, false], [123, "hub", 4], [123, "audio", 2, 1280]]);
  assert.ok(bodies.every((body) => body.length < 400));
});

test("failed trace posting retains the sample for the next attempt", async () => {
  const bodies: string[] = [];
  let fail = true;
  const trace = new HardwareTrace({ endpoint: "/debug", session: "cal", now: () => 456,
    post: async (_url, body) => {
      if (fail) throw new Error("offline");
      bodies.push(body);
    },
  });
  trace.record("imu", 0.1, 0.2, 0.3);
  await trace.flush();
  fail = false;
  await trace.flush();
  assert.deepEqual(JSON.parse(bodies[0]!).events, [[456, "imu", 0.1, 0.2, 0.3]]);
});
