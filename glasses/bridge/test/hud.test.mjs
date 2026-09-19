import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildSnapshot,
  normaliseStatus,
  orderAgents,
  projectAgent,
  shouldWake,
  summarise,
} from "../src/hud.mjs";

test("status aliases collapse onto the attention vocabulary", () => {
  assert.equal(normaliseStatus("Waiting"), "blocked");
  assert.equal(normaliseStatus("permission_required"), "blocked");
  assert.equal(normaliseStatus("running"), "working");
  assert.equal(normaliseStatus("COMPLETED"), "done");
  assert.equal(normaliseStatus("crashed"), "failed");
  assert.equal(normaliseStatus("something-new"), "unknown");
  assert.equal(normaliseStatus(undefined), "unknown");
});

test("agents are projected from loose Host field spellings", () => {
  const agent = projectAgent({ pane_id: "w1:pT", custom_name: "auth", label: "herden", status: "busy" });
  assert.deepEqual(agent, {
    id: "w1:pT",
    name: "auth",
    space: "herden",
    status: "working",
    pinned: false,
  });
});

test("pane ids are treated as opaque strings", () => {
  // Observed captures include uppercase and varied shapes; no grammar is parsed.
  for (const id of ["w1:pT", "w1C:p1", "wR:pC", "wV:p1H", "%3"]) {
    assert.equal(projectAgent({ pane_id: id }).id, id);
  }
});

test("ordering puts urgency first, then pins, then name", () => {
  const ordered = orderAgents([
    { id: "1", name: "zeta", status: "working", pinned: false },
    { id: "2", name: "alpha", status: "blocked", pinned: false },
    { id: "3", name: "beta", status: "working", pinned: true },
    { id: "4", name: "gamma", status: "idle", pinned: false },
  ]);
  assert.deepEqual(ordered.map((a) => a.name), ["alpha", "beta", "zeta", "gamma"]);
});

test("only transitions into an attention state wake the display", () => {
  const blocked = { status: "blocked" };
  const working = { status: "working" };
  assert.equal(shouldWake(working, blocked), true, "working -> blocked wakes");
  assert.equal(shouldWake(blocked, blocked), false, "repeat of a shown state does not");
  assert.equal(shouldWake(blocked, working), false, "working never wakes");
  assert.equal(shouldWake(undefined, { status: "done" }), true, "first sight of done wakes");
  assert.equal(shouldWake(undefined, { status: "idle" }), false, "idle never wakes");
});

test("snapshot reports which agents newly want attention", () => {
  const previous = new Map([["a", { id: "a", status: "working" }]]);
  const snapshot = buildSnapshot(
    [
      { pane_id: "a", name: "one", status: "blocked" },
      { pane_id: "b", name: "two", status: "working" },
    ],
    previous,
  );
  assert.deepEqual(snapshot.wake, ["a"]);
  assert.equal(snapshot.agents.length, 2);
});

test("agents without an id are dropped rather than rendered blank", () => {
  const snapshot = buildSnapshot([{ name: "ghost", status: "idle" }]);
  assert.deepEqual(snapshot.agents, []);
});

test("the glance summary stays within the lens budget", () => {
  const agents = orderAgents(
    Array.from({ length: 12 }, (_, i) => ({
      id: String(i),
      name: `agent-${i}`,
      status: ["blocked", "working", "idle", "done"][i % 4],
      pinned: false,
    })),
  );
  const line = summarise(agents);
  assert.ok(line.length < 60, `summary too long for the lens: ${line}`);
  assert.equal(summarise([]), "no agents");
});

test("a real 0.9.6 agent.list record projects correctly", () => {
  // Captured live from a herden 0.9.6 Host (protocol 22). There is no name
  // field; the title carries the label and cwd carries the recognisable space.
  const agent = projectAgent({
    terminal_id: "term_65b45e116ebe7b",
    agent: "claude",
    terminal_title: "◑ Even G2 glasses development setup",
    terminal_title_stripped: "Even G2 glasses development setup",
    agent_status: "working",
    workspace_id: "w3X",
    tab_id: "w3X:t1",
    pane_id: "w3X:p1",
    focused: true,
    cwd: "/home/ted/src/github.com/3loc/herden",
    revision: 13,
  });
  assert.deepEqual(agent, {
    id: "w3X:p1",
    name: "Even G2 glasses development setup",
    space: "herden",
    status: "working",
    pinned: false,
  });
});

test("a record with neither title nor cwd still renders something", () => {
  const agent = projectAgent({ pane_id: "w1:pT", agent_status: "done" });
  assert.equal(agent.name, "w1:pT");
  assert.equal(agent.space, "");
});
