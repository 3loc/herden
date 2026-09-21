import assert from "node:assert/strict";
import { test } from "node:test";
import { getTextWidth } from "@evenrealities/pretext";
import { byAttention, COLS, LENS_TEXT_WIDTH, ROWS, brightnessFor, compactOutputLines, harnessLabel, harnessMark, outputWindowSize, renderDetail, renderGestureDebug, renderList, renderSpaceCard, spaceMessage, truncate, windowAround, wrapOutputRows } from "../src/hud.ts";
import { parseHiddenSpaces, serialiseHiddenSpaces, visibleSnapshot } from "../src/selection.ts";
import type { Agent, Snapshot } from "../src/protocol.ts";
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
    for (const line of lines) assert.ok(getTextWidth(line) <= LENS_TEXT_WIDTH, `line too wide: ${line}`);
  }
});

test("the native text layout reserves a bottom status row without firmware scrolling", () => {
  assert.equal(ROWS, 10);
  assert.equal(COLS, 48);
  assert.equal(outputWindowSize(), 8);
});

test("blank terminal rows do not consume a lens row", () => {
  assert.deepEqual(compactOutputLines("first\n\n \nsecond\n"), ["first", "second"]);
});

test("wide terminal text becomes physical rows before the bottom page is selected", () => {
  const wide = "W".repeat(48); // 48 characters, but 768 pixels in the G2 font.
  const rows = wrapOutputRows(["old", wide, "newest line"]);
  assert.ok(rows.length > 3);
  assert.equal(rows[0], "old");
  assert.equal(rows.at(-1), "newest line");
  assert.equal(rows.filter((row) => row.includes("W")).join(""), wide);
  for (const row of rows) assert.ok(getTextWidth(row) <= LENS_TEXT_WIDTH, row);
});

test("an opened Space renders the latest wrapped output and fixed footer", () => {
  const rows = wrapOutputRows(Array.from({ length: 20 }, (_, index) => `line ${index + 1} ${"W".repeat(48)}`));
  const frame = renderDetail(agent(), rows, rows.length - outputWindowSize(), true);
  const visible = frame.split("\n");
  assert.equal(visible.length, ROWS);
  assert.ok(visible.some((row) => row.includes("line 20")), frame);
  assert.match(visible.at(-1)!, new RegExp(`${rows.length}/${rows.length}`));
  for (const row of visible) assert.ok(getTextWidth(row) <= LENS_TEXT_WIDTH, row);
});

test("over-long text is ellipsised rather than wrapped", () => {
  assert.equal(truncate("abcdef", 4), "abc…");
  assert.equal(truncate("abc", 4), "abc");
  assert.equal(truncate("åäö🦌", 4), "åäö🦌");
  assert.equal(truncate("åäö🦌x", 4), "åäö…");
});

test("the list marks the selected row with the cursor column", () => {
  const view = renderList(
    snapshot([agent({ name: "one", space: "Build", status: "blocked" }), agent({ id: "b", name: "two", space: "Glasses" })]),
    1,
    true,
  );
  const lines = view.split("\n");
  assert.equal(lines[0]!, " 1 QUESTION Shell · host · one");
  assert.equal(lines[1]!, ">2 WORK Shell · host · two");
  assert.equal(lines.at(-1), "MIC OFF · 2 Spaces");
});

test("the lens row spells out every status without brackets", () => {
  assert.equal(
    renderSpaceCard(agent({ kind: "claude", hostName: "host-a", name: "Herden right space file sharing", space: "herden" }), true, 5),
    ">5 WORK Claude · host-a · Herden right space fi…",
  );
  assert.equal(
    renderSpaceCard(agent({ kind: "codex", hostName: "host-a", name: "fleet", space: "fleet", status: "idle" }), false),
    " 1 IDLE Codex · host-a · fleet",
  );
});

test("the spoken row number is the visible position without faux columns", () => {
  const twelve = renderSpaceCard(agent({ kind: "codex", hostName: "host-a", name: "fleet", space: "fleet", status: "idle" }), false, 12);
  assert.equal(twelve, " 12 IDLE Codex · host-a · fleet");
  assert.equal(renderSpaceCard(agent({ status: "idle" }), false, 1).slice(0, 3), " 1 ");
});

test("the list numbers rows by their visible position, not by Host id", () => {
  const many = Array.from({ length: 30 }, (_, index) =>
    agent({ id: `w${index}:pA`, name: `space-${index}`, status: "idle" }));
  const lines = renderList(snapshot(many), 20, true).split("\n");
  const numbers = lines.slice(0, -1).map((line) => Number(line.match(/^.([0-9]+)/)?.[1]));
  // The window scrolled, so the visible numbers run on from wherever it starts.
  assert.deepEqual(numbers, numbers.map((_, index) => numbers[0]! + index));
  assert.ok(numbers[0]! > 1, `expected a scrolled window: ${numbers[0]}`);
  // The cursor sits on the row whose number is the selection's position.
  const cursor = lines.findIndex((line) => line.startsWith(">"));
  assert.equal(numbers[cursor], 21);
});

test("status words are plain, including IDLE", () => {
  const labels: Record<Agent["status"], string> = {
    working: "WORK", idle: "IDLE", blocked: "QUESTION", failed: "ERROR", done: "DONE", unknown: "?",
  };
  for (const [status, label] of Object.entries(labels) as [Agent["status"], string][]) {
    const row = renderSpaceCard(agent({ kind: "codex", hostName: "host-a", status }), false, 7);
    assert.ok(row.startsWith(` 7 ${label} Codex · host-a · `), `${status}: ${row}`);
  }
  assert.equal(renderSpaceCard(agent({ status: "idle" }), false, 7), " 7 IDLE Shell · host · auth");
});

test("the same roster renders identically, so nothing repaints on its own", () => {
  const roster = snapshot([agent({ kind: "codex", hostName: "host-a" })]);
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
  assert.equal(harnessLabel("codex"), "Codex");
  assert.equal(harnessLabel("claude"), "Claude");
  assert.equal(harnessLabel(undefined), "Shell");
});

test("the message is the Host's terminal title, falling back to the Space", () => {
  assert.equal(spaceMessage(agent({ name: "Herden right space file sharing", space: "herden" })), "Herden right space file sharing");
  assert.equal(spaceMessage(agent({ name: "herden", space: "herden" })), "herden");
  assert.equal(spaceMessage(agent({ name: "", space: "" })), "Unnamed Space");
});

test("a long message is truncated, never the status or spoken number", () => {
  for (const position of [5, 12]) {
    const row = renderSpaceCard(agent({ kind: "codex", hostName: "host-a", name: "x".repeat(200), space: "herden" }), true, position);
    assert.equal(row.length, COLS);
    assert.ok(row.startsWith(`>${position} WORK Codex · host-a · `), row);
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

test("detail shows the last output row and anchors status below it", () => {
  const output = Array.from({ length: outputWindowSize() + 3 }, (_, index) => `line ${index + 1}`);
  const detail = renderDetail(agent({ hostName: "host-b", kind: "pi", name: "Deploy", space: "Deploy", status: "blocked" }), output, 3, true, 5);
  // The open Space keeps the number the wearer would have spoken.
  assert.match(detail, /^5  Deploy · Pi · host-b/m);
  assert.match(detail, /line 5/);
  assert.match(detail, new RegExp(`line ${output.length}`));
  assert.equal(detail.split("\n").at(-1), `MIC OFF · QUESTION · ${output.length}/${output.length}`);
  assert.equal(renderDetail(agent({ status: "idle" }), ["ready"], 0, true).split("\n").at(-1), "MIC OFF · IDLE · 1/1");
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
  assert.equal(frame.split("\n")[0], ">1 QUESTION Shell · host · host-release");
});

const roster = snapshot([
  agent({ id: "host-a:w1:pA", space: "herden", hostName: "host-a", kind: "codex" }),
  agent({ id: "host-a:w2:pB", space: "fleet", hostName: "host-a", kind: "claude", status: "idle" }),
]);

test("hidden Spaces leave the lens list and the wake, not the roster", () => {
  const projected = visibleSnapshot({ ...roster, wake: ["host-a:w1:pA", "host-a:w2:pB"] }, new Set(["host-a:w1:pA"]));
  assert.deepEqual(projected.agents.map((a) => a.id), ["host-a:w2:pB"]);
  assert.deepEqual(projected.wake, ["host-a:w2:pB"]);
  assert.equal(projected.summary, "1 Space");
  // The panel keeps rendering every Space the Hosts reported.
  assert.equal(roster.agents.length, 2);
  assert.doesNotMatch(renderList(projected, 0, true), /herden/);
});

test("an unknown hidden id is tolerated rather than dropping a Space", () => {
  assert.deepEqual(visibleSnapshot(roster, new Set(["gone:w9:pZ"])).agents.length, 2);
});

test("hiding every Space says so instead of rendering an empty frame", () => {
  const nothing = visibleSnapshot(roster, new Set(["host-a:w1:pA", "host-a:w2:pB"]));
  assert.equal(nothing.agents.length, 0);
  const frame = renderList(nothing, 0, true, "no Spaces selected");
  assert.equal(frame.split("\n")[0], "no Spaces selected");
  assert.equal(frame.split("\n").at(-1), "MIC OFF · 0 Spaces");
});

test("the stored selection is hidden ids, parsed leniently", () => {
  assert.deepEqual([...parseHiddenSpaces('["host-a:w1:pA"]')], ["host-a:w1:pA"]);
  assert.deepEqual([...parseHiddenSpaces(null)], []);
  assert.deepEqual([...parseHiddenSpaces("not json")], []);
  assert.deepEqual([...parseHiddenSpaces('{"a":1}')], []);
  assert.deepEqual([...parseHiddenSpaces('["ok", 7, "", null]')], ["ok"]);
  assert.equal(serialiseHiddenSpaces(new Set(["b", "a"])), '["a","b"]');
  // A Space absent from storage is rendered: only hidden ids are persisted.
  assert.equal(visibleSnapshot(roster, parseHiddenSpaces("[]")).agents.length, 2);
});

test("questions sort above idle, and working sinks to the foot", () => {
  const agent = (status, space, hostName = "host-a") =>
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
  const sorted = [agent("zeta", "host-b"), agent("alpha", "host-b"), agent("beta", "host-a")].sort(byAttention);
  assert.deepEqual(sorted.map((a) => `${a.hostName}:${a.space}`), ["host-a:beta", "host-b:alpha", "host-b:zeta"]);
});

test("the temporary gesture diagnostic stays above the persistent status footer", () => {
  const roster = snapshot([agent({ kind: "codex", hostName: "host-a" })]);
  const debugged = renderList(roster, 0, true, "no agents", renderGestureDebug({ count: 7, field: "sysEvent", eventType: 1 }));
  const lines = debugged.split("\n");
  assert.ok(lines.includes("ev#7 sysEvent type=1"));
  assert.equal(lines.at(-1), "MIC OFF · 1 Space");
  assert.ok(lines.length <= ROWS);
  for (const line of lines) assert.ok(line.length <= COLS, line);
  // The flag is off: no diagnostic argument, no diagnostic row.
  assert.equal(renderList(roster, 0, true).split("\n")[0], ">1 WORK Codex · host-a · auth");
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
  assert.equal(lines.at(-2), "ev#1 sysEvent type=0");
  assert.equal(lines.at(-1), "MIC OFF · 30 Spaces · offline");
  assert.ok(lines.some((line) => line.startsWith(">30 IDLE Shell")), lines.join("|"));
});

test("an unreadable Space surfaces its failure as one detail line", () => {
  const detail = renderDetail(agent({ hostName: "host-a", kind: "claude" }), compactOutputLines("read output failed: 503"), 0, true, 2);
  const lines = detail.split("\n");
  assert.equal(lines[1], "read output failed: 503");
  for (const line of lines) assert.ok(line.length <= COLS, line);
});
