import assert from "node:assert/strict";
import { test } from "node:test";
import { COLS, ROWS, brightnessFor, compactOutputLines, harnessMark, outputWindowSize, renderDetail, renderList, renderSpaceCard, spaceMessage, truncate, windowAround } from "../src/hud.ts";
import { parseHiddenSpaces, serialiseHiddenSpaces, visibleSnapshot } from "../src/selection.ts";
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

test("the list marks the selected row with the cursor column", () => {
  const view = renderList(
    snapshot([agent({ name: "one", space: "Build", status: "blocked" }), agent({ id: "b", name: "two", space: "Glasses" })]),
    1,
    true,
  );
  const lines = view.split("\n");
  assert.equal(lines[0]!, "    [Zsh][host]:one");
  assert.equal(lines[1]!, ">[W][Zsh][host]:two");
});

test("the lens row is cursor, work flash, harness, Host, message", () => {
  assert.equal(
    renderSpaceCard(agent({ kind: "claude", hostName: "3loc", name: "Herden right space file sharing", space: "herden" }), true, 0),
    ">[W][C][3loc]:Herden right space file sharing",
  );
  assert.equal(
    renderSpaceCard(agent({ kind: "codex", hostName: "3loc", name: "fleet", space: "fleet", status: "idle" }), false, 0),
    "    [Cdx][3loc]:fleet",
  );
});

test("only a working Space flashes, and only on alternate snapshots", () => {
  const working = agent({ kind: "codex", hostName: "3loc", status: "working" });
  assert.match(renderSpaceCard(working, false, 0), /^ \[W\]\[Cdx\]/);
  assert.match(renderSpaceCard(working, false, 1), /^ {4}\[Cdx\]/);
  assert.match(renderSpaceCard(working, false, 2), /^ \[W\]\[Cdx\]/);
  // Columns never jump: the blank phase is exactly three spaces wide.
  assert.equal(renderSpaceCard(working, false, 0).length, renderSpaceCard(working, false, 1).length);
  for (const status of ["idle", "blocked", "failed", "done", "unknown"] as const) {
    const row = renderSpaceCard(agent({ kind: "codex", status }), false, 0);
    assert.doesNotMatch(row, /\[W\]/, status);
    assert.match(row, /^ {4}\[Cdx\]/, status);
  }
});

test("snapshot arrivals drive the flash, so the frame text alternates", () => {
  const roster = snapshot([agent({ kind: "codex", hostName: "3loc" })]);
  assert.notEqual(renderList(roster, 0, true, 0), renderList(roster, 0, true, 1));
  assert.equal(renderList(roster, 0, true, 0), renderList(roster, 0, true, 2));
  const quiet = snapshot([agent({ kind: "codex", hostName: "3loc", status: "idle" })]);
  assert.equal(renderList(quiet, 0, true, 0), renderList(quiet, 0, true, 1));
});

test("harness marks follow Herden's own vocabulary", () => {
  assert.equal(harnessMark("codex"), "Cdx");
  assert.equal(harnessMark("claude"), "C");
  assert.equal(harnessMark("pi"), "Pi");
  assert.equal(harnessMark("zsh"), "Zsh");
  assert.equal(harnessMark("bash"), "Bash");
  assert.equal(harnessMark("fish"), "Fish");
  // A pane with no interactive Agent is the wearer's shell.
  assert.equal(harnessMark(undefined), "Zsh");
  assert.equal(harnessMark("agent"), "Zsh");
  assert.equal(harnessMark("GEMINI"), "Gem");
});

test("the message is the Host's terminal title, falling back to the Space", () => {
  assert.equal(spaceMessage(agent({ name: "Herden right space file sharing", space: "herden" })), "Herden right space file sharing");
  assert.equal(spaceMessage(agent({ name: "herden", space: "herden" })), "herden");
  assert.equal(spaceMessage(agent({ name: "", space: "" })), "Unnamed Space");
});

test("a long message is truncated, never the brackets", () => {
  const row = renderSpaceCard(agent({ kind: "codex", hostName: "3loc", name: "x".repeat(200), space: "herden" }), true, 0);
  assert.equal(row.length, COLS);
  assert.ok(row.startsWith(">[W][Cdx][3loc]:"), row);
  assert.ok(row.endsWith("…"), row);
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
  const detail = renderDetail(agent({ hostName: "fansvine", kind: "pi", name: "Deploy", space: "Deploy", status: "blocked" }), output, 3, true);
  assert.match(detail, /^\[Pi\]\[fansvine\]:Deploy/m);
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
  // The fixture's title differs from its Space, so the title is the message.
  assert.equal(frame, ">   [Zsh][host]:host-release");
});

const roster = snapshot([
  agent({ id: "3loc:w1:pA", space: "herden", hostName: "3loc", kind: "codex" }),
  agent({ id: "3loc:w2:pB", space: "fleet", hostName: "3loc", kind: "claude", status: "idle" }),
]);

test("hidden Spaces leave the lens list and the wake, not the roster", () => {
  const projected = visibleSnapshot({ ...roster, wake: ["3loc:w1:pA", "3loc:w2:pB"] }, new Set(["3loc:w1:pA"]));
  assert.deepEqual(projected.agents.map((a) => a.id), ["3loc:w2:pB"]);
  assert.deepEqual(projected.wake, ["3loc:w2:pB"]);
  assert.equal(projected.summary, "1 Space");
  // The panel keeps rendering every Space the Hosts reported.
  assert.equal(roster.agents.length, 2);
  assert.doesNotMatch(renderList(projected, 0, true, 0), /herden/);
});

test("an unknown hidden id is tolerated rather than dropping a Space", () => {
  assert.deepEqual(visibleSnapshot(roster, new Set(["gone:w9:pZ"])).agents.length, 2);
});

test("hiding every Space says so instead of rendering an empty frame", () => {
  const nothing = visibleSnapshot(roster, new Set(["3loc:w1:pA", "3loc:w2:pB"]));
  assert.equal(nothing.agents.length, 0);
  const frame = renderList(nothing, 0, true, 0, "no Spaces selected");
  assert.equal(frame, "no Spaces selected");
});

test("the stored selection is hidden ids, parsed leniently", () => {
  assert.deepEqual([...parseHiddenSpaces('["3loc:w1:pA"]')], ["3loc:w1:pA"]);
  assert.deepEqual([...parseHiddenSpaces(null)], []);
  assert.deepEqual([...parseHiddenSpaces("not json")], []);
  assert.deepEqual([...parseHiddenSpaces('{"a":1}')], []);
  assert.deepEqual([...parseHiddenSpaces('["ok", 7, "", null]')], ["ok"]);
  assert.equal(serialiseHiddenSpaces(new Set(["b", "a"])), '["a","b"]');
  // A Space absent from storage is rendered: only hidden ids are persisted.
  assert.equal(visibleSnapshot(roster, parseHiddenSpaces("[]")).agents.length, 2);
});
