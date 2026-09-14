---
status: accepted
---

# Unified Space-first Console over the general Host model

Herden presents one list of Spaces. Each Space is one durable destination whose
primary terminal currently contains either an Agent or an ordinary shell.
Agent kind and status are properties of that Space row, not a second navigation
hierarchy.

## Why

Herden's observed phone and desktop workflow is overwhelmingly one Agent in the
root pane of one Space. Showing Spaces and their detected Agents in equal,
separate lists repeats the same names and statuses while consuming half of a
narrow screen. The Space name carries the human meaning of the work; an Agent
kind such as Codex is usually supporting metadata.

Herdr's general workspace, tab and pane model remains useful as a compatibility
and automation substrate. Removing it would make upstream synchronization
harder without making Herden simpler to use, so this decision changes only
creation defaults and presentation.

## Behaviour

- The Console lists every known Space, including shell-only Spaces.
- A row leads with the Space label and shows `Terminal`, one Agent kind and
  status, or an Agent count when legacy topology contains several Agents.
- New Agent creates a new Space and launches in its existing root pane. New
  Terminal creates a shell-only Space. Neither flow asks for tabs or splits.
- Split creation is absent from the pane menu and its default keybindings are
  empty. The API and configurable split actions remain compatibility surfaces.
- Agent attention remains automatic: pinned Spaces first, then Blocked, Done,
  Working, Idle and terminal-only Spaces, with stable labels as tie-breakers.
- Advanced and legacy topology remains reachable. Existing tabs, panes,
  multi-Agent Spaces and linked Worktrees are not migrated or deleted.
- The Host sidebar uses the same single-list projection. Its Space row carries
  the Agent kind, `terminal`, or an Agent count; the duplicate Agent panel and
  its `grouped` / `priority` switch are not part of Herden's primary UI. The
  rendering path remains available through the advanced
  `ui.show_separate_agent_panel` compatibility setting.

## Boundaries

Wire identities remain Host plus pane for Agent attachment, notifications,
sharing and pins, and Host plus workspace for Space lifecycle. A display label
is never a routing key. Closing an Agent still closes its pane; closing a Space
still uses the Host's workspace lifecycle and worktree-group safeguards.

The runtime retains workspace, tab and pane APIs so upstream imports and
automation remain compatible. This ADR does not authorize flattening persisted
layouts, deleting extra panes, or weakening ambiguous-outcome safety.
