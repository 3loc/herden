import assert from "node:assert/strict";
import { test } from "node:test";
import { byAttention, COLS, ROWS, brightnessFor, compactOutputLines, harnessMark, outputWindowSize, positionMark, renderDetail, renderGestureDebug, renderList, renderSpaceCard, spaceMessage, truncate, windowAround } from "../src/hud.ts";
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
  assert.equal(lines[0]!, "  1[Q][Zsh][host]:one");
  assert.equal(lines[1]!, "> 2[W][Zsh][host]:two");
});

test("the lens row is cursor, number, status, harness, Host, message", () => {
  assert.equal(
    renderSpaceCard(agent({ kind: "claude", hostName: "3loc", name: "Herden right space file sharing", space: "herden" }), true, 5),
    "> 5[W][C][3loc]:Herden right space file sharing",
  );
  assert.equal(
    renderSpaceCard(agent({ kind: "codex", hostName: "3loc", name: "fleet", space: "fleet", status: "idle" }), false),
    "  1[I][Cdx][3loc]:fleet",
  );
});

test("the spoken row number is the visible position, two columns wide", () => {
  assert.equal(positionMark(5), " 5");
  assert.equal(positionMark(12), "12");
  const twelve = renderSpaceCard(agent({ kind: "codex", hostName: "agneta", name: "fleet", space: "fleet", status: "idle" }), false, 12);
  assert.equal(twelve, " 12[I][Cdx][agneta]:fleet");
  // Past nine the brackets stay in the same columns as row one.
  assert.equal(twelve.indexOf("["), renderSpaceCard(agent({ status: "idle" }), false, 1).indexOf("["));
});

test("the list numbers rows by their visible position, not by Host id", () => {
  const many = Array.from({ length: 30 }, (_, index) =>
    agent({ id: `w${index}:pA`, name: `space-${index}`, status: "idle" }));
  const lines = renderList(snapshot(many), 20, true).split("\n");
  const numbers = lines.map((line) => Number(line.slice(1, 3).trim()));
  // The window scrolled, so the visible numbers run on from wherever it starts.
  assert.deepEqual(numbers, numbers.map((_, index) => numbers[0]! + index));
  assert.ok(numbers[0]! > 1, `expected a scrolled window: ${numbers[0]}`);
  // The cursor sits on the row whose number is the selection's position.
  const cursor = lines.findIndex((line) => line.startsWith(">"));
  assert.equal(numbers[cursor], 21);
});

test("every status renders one three-character bracket", () => {
  const letters: Record<Agent["status"], string> = {
    working: "[W]", idle: "[I]", blocked: "[Q]", failed: "[F]", done: "[D]", unknown: "[?]",
  };
  for (const [status, letter] of Object.entries(letters) as [Agent["status"], string][]) {
    const row = renderSpaceCard(agent({ kind: "codex", hostName: "3loc", status }), false, 7);
    assert.ok(row.startsWith(`  7${letter}[Cdx][3loc]:`), `${status}: ${row}`);
  }
  // Nothing jumps: every row's brackets occupy the same columns.
  const widths = new Set(Object.keys(letters).map((status) =>
    renderSpaceCard(agent({ kind: "codex", hostName: "3loc", status: status as Agent["status"], name: "x", space: "x" })).length));
  assert.equal(widths.size, 1);
});

test("the same roster renders identically, so nothing repaints on its own", () => {
  const roster = snapshot([agent({ kind: "codex", hostName: "3loc" })]);
  assert.equal(renderList(roster, 0, true), renderList(roster, 0, true));
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

test("a long message is truncated, never the brackets or the number", () => {
  for (const position of [5, 12]) {
    const row = renderSpaceCard(agent({ kind: "codex", hostName: "3loc", name: "x".repeat(200), space: "herden" }), true, position);
    assert.equal(row.length, COLS);
    assert.ok(row.startsWith(`>${positionMark(position)}[W][Cdx][3loc]:`), row);
    assert.ok(row.endsWith("…"), row);
  }
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
  const detail = renderDetail(agent({ hostName: "fansvine", kind: "pi", name: "Deploy", space: "Deploy", status: "blocked" }), output, 3, true, 5);
  // The open Space keeps the number the wearer would have spoken.
  assert.match(detail, /^5\[Pi\]\[fansvine\]:Deploy/m);
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
  assert.equal(frame, "> 1[Q][Zsh][host]:host-release");
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
  assert.doesNotMatch(renderList(projected, 0, true), /herden/);
});

test("an unknown hidden id is tolerated rather than dropping a Space", () => {
  assert.deepEqual(visibleSnapshot(roster, new Set(["gone:w9:pZ"])).agents.length, 2);
});

test("hiding every Space says so instead of rendering an empty frame", () => {
  const nothing = visibleSnapshot(roster, new Set(["3loc:w1:pA", "3loc:w2:pB"]));
  assert.equal(nothing.agents.length, 0);
  const frame = renderList(nothing, 0, true, "no Spaces selected");
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

test("questions sort above idle, and working sinks to the foot", () => {
  const agent = (status, space, hostName = "3loc") =>
    ({ id: space, name: space, kind: "claude", space, status, pinned: false, hostName });
  const sorted = [
    agent("working", "busy"), agent("idle", "quiet"), agent("blocked", "asking"),
    agent("done", "finished"), agent("failed", "broken"), agent("unknown", "mystery"),
  ].sort(byAttention);
  assert.deepEqual(sorted.map((a) => a.space), ["asking", "broken", "finished", "quiet", "mystery", "busy"]);
});

test("a tie breaks by Host then Space, so rows never shuffle", () => {
  const agent = (space, hostName) =>
    ({ id: space, name: space, kind: "claude", space, status: "idle", pinned: false, hostName });
  const sorted = [agent("zeta", "vinux"), agent("alpha", "vinux"), agent("beta", "agneta")].sort(byAttention);
  assert.deepEqual(sorted.map((a) => `${a.hostName}:${a.space}`), ["agneta:beta", "vinux:alpha", "vinux:zeta"]);
});

test("the temporary gesture diagnostic is the last lens row", () => {
  const roster = snapshot([agent({ kind: "codex", hostName: "3loc" })]);
  const debugged = renderList(roster, 0, true, "no agents", renderGestureDebug({ count: 7, field: "sysEvent", eventType: 1 }));
  const lines = debugged.split("\n");
  assert.equal(lines.at(-1), "ev#7 sysEvent type=1");
  assert.ok(lines.length <= ROWS);
  for (const line of lines) assert.ok(line.length <= COLS, line);
  // The flag is off: no diagnostic argument, no diagnostic row.
  assert.equal(renderList(roster, 0, true), "> 1[W][Cdx][3loc]:auth");
});

test("the diagnostic states what arrived, including nothing and a failure", () => {
  assert.equal(renderGestureDebug({ count: 0, field: "none" }), "ev#0 none yet");
  assert.equal(renderGestureDebug({ count: 3, field: "listEvent", eventType: 0 }), "ev#3 listEvent type=0");
  assert.equal(renderGestureDebug({ count: 4, field: "audioEvent" }), "ev#4 audioEvent type=?");
  assert.equal(renderGestureDebug({ count: 5, field: "sysEvent", eventType: 0, error: "read failed" }), "ev#5 sysEvent err read failed");
  assert.equal(renderGestureDebug({ count: 6, field: "sysEvent", error: "x".repeat(200) }).length, COLS);
});

test("the diagnostic row never displaces the selected Space", () => {
  const many = Array.from({ length: 30 }, (_, index) => agent({ id: `w${index}`, name: `space-${index}`, status: "idle" }));
  const lines = renderList(snapshot(many), 29, false, "no agents", "ev#1 sysEvent type=0").split("\n");
  assert.equal(lines.length, ROWS);
  assert.equal(lines[0], "Host offline");
  assert.equal(lines.at(-1), "ev#1 sysEvent type=0");
  assert.ok(lines.some((line) => line.startsWith(">30[I]")), lines.join("|"));
});

test("an unreadable Space surfaces its failure as one detail line", () => {
  const detail = renderDetail(agent({ hostName: "3loc", kind: "claude" }), compactOutputLines("read output failed: 503"), 0, true, 2);
  const lines = detail.split("\n");
  assert.equal(lines[1], "read output failed: 503");
  for (const line of lines) assert.ok(line.length <= COLS, line);
});
