import assert from "node:assert/strict";
import { test } from "node:test";
import { COLS, ROWS, brightnessFor, compactOutputLines, outputWindowSize, renderDetail, renderList, renderSpaceCard, truncate, windowAround } from "../src/hud.ts";
import type { Agent, Snapshot } from "../src/protocol.ts";
import { PIXEL_COLS, PIXEL_ROWS, pixelGlyph } from "../src/pixel-font.ts";
import fixture from "../../protocol/hud-v1.json" with { type: "json" };

const agent = (over: Partial<Agent> = {}): Agent => ({
  id: "w1:pT",
  name: "auth",
  space: "herden",
  status: "working",
  pinned: false,
  ...over,
});

const snapshot = (agents: Agent[], summary = "1 working"): Snapshot => ({
  protocol_version: 1,
  type: "snapshot",
  revision: 1,
  at: 0,
  inventory_valid: true,
  stale: false,
  controls_allowed: false,
  agents,
  wake: [],
  summary,
});

test("every rendered frame fits the lens budget", () => {
  const many = Array.from({ length: 20 }, (_, i) =>
    agent({ id: String(i), name: `agent-number-${i}`, status: i % 2 ? "blocked" : "working" }),
  );
  for (const view of [renderList(snapshot(many), 7, true), renderDetail(many[0]!, ["one", "two"], 0, true)]) {
    const lines = view.split("\n");
    assert.ok(lines.length <= ROWS, `too many rows: ${lines.length}`);
    for (const line of lines) assert.ok(line.length <= COLS, `line too wide: ${line}`);
  }
});

test("the bitmap terminal fits the lens grid", () => {
  assert.equal(ROWS, PIXEL_ROWS);
  assert.equal(COLS, PIXEL_COLS);
  assert.notDeepEqual(pixelGlyph("a"), pixelGlyph("A"));
  assert.equal(pixelGlyph("A").length, 14);
  assert.equal(pixelGlyph("A")[3], 0x10);
});

test("blank terminal rows do not consume a lens row", () => {
  assert.deepEqual(compactOutputLines("first\n\n \nsecond\n"), ["first", "second"]);
});

test("over-long text is ellipsised rather than wrapped", () => {
  assert.equal(truncate("abcdef", 4), "abc…");
  assert.equal(truncate("abc", 4), "abc");
});

test("the list marks the selected Space and its status", () => {
  const view = renderList(
    snapshot([agent({ name: "one", space: "Build", status: "blocked" }), agent({ id: "b", name: "two", space: "Glasses" })]),
    1,
    true,
  );
  const lines = view.split("\n");
  assert.match(lines[0]!, /^ host:agent:Build:blocked$/);
  assert.match(lines[1]!, /^>host:agent:Glasses:working$/);
});

test("Space cards omit the agent and branch-derived display names", () => {
  const card = renderSpaceCard(agent({ name: "feature/glasses", space: "Glasses support" }), true);
  assert.match(card, /Glasses support/);
  assert.doesNotMatch(card, /feature\/glasses/);
});

test("the lens keeps one dense host:agent:space:state list", () => {
  const view = renderList(snapshot([
    agent({ id: "a", space: "fleet", hostName: "3loc", kind: "codex", status: "done" }),
    agent({ id: "b", space: "deploy", hostName: "fansvine", kind: "claude" }),
  ]), 0, true);
  assert.match(view, />3loc:codex:fleet:done\n fansvine:claude:deploy:working/);
});

test("an offline stream is visible rather than silently stale", () => {
  assert.match(renderList(snapshot([agent()]), 0, false), /offline/);
  assert.match(renderDetail(agent(), ["No output"], 0, false), /offline/);
});

test("an empty roster says so instead of rendering blank", () => {
  assert.match(renderList(snapshot([], "no agents"), 0, true), /no agents/);
});

test("detail shows the selected Space's scrollable output and one back gesture", () => {
  const output = Array.from({ length: outputWindowSize() + 3 }, (_, index) => `line ${index + 1}`);
  const detail = renderDetail(agent({ hostName: "fansvine", kind: "pi", space: "Deploy", status: "blocked" }), output, 3, true);
  assert.match(detail, /^fansvine:pi:Deploy/m);
  assert.match(detail, /line 4/);
  assert.match(detail, new RegExp(`line ${output.length}`));
  assert.match(detail, new RegExp(`4-${output.length}/${output.length}`));
  assert.match(detail, /! blocked/);
  assert.match(detail, /double tap: back/);
  assert.doesNotMatch(detail, /Send Enter|interrupt|long press/i);
});

test("the scroll window keeps the selection on screen at both ends", () => {
  const items = Array.from({ length: 20 }, (_, i) => i);
  assert.deepEqual(windowAround(items, 0, 5).items, [0, 1, 2, 3, 4]);
  assert.deepEqual(windowAround(items, 19, 5).items, [15, 16, 17, 18, 19]);
  assert.ok(windowAround(items, 10, 5).items.includes(10));
  assert.deepEqual(windowAround([1, 2], 0, 5), { start: 0, items: [1, 2] });
});

test("brightness goes full only when a decision is pending", () => {
  assert.equal(brightnessFor([agent({ status: "working" })]), 2);
  assert.equal(brightnessFor([agent({ status: "blocked" })]), 4);
  assert.equal(brightnessFor([agent({ status: "failed" })]), 4);
});

test("the shared v1 fixture remains renderable", () => {
  const frame = renderList(fixture as Snapshot, 0, true);
  assert.match(frame, /runtime/);
});
