---
status: superseded by ADR 0022
---

# Agent-first iOS Console, without runtime one-to-one enforcement

iOS presents Agents as its primary destinations. A Space is context, not a
second card for the same work. The runtime still supports multiple Agents and
shell panes in one Space.

## Why

Herden's iOS app targets vibecoders who are not necessarily fluent in
terminals or workspace management. One Agent with one automatically created
Space removes a separate setup decision and gives the user one named place
to return to. This is an opinionated product direction from Herden's Heeler
origins, not a requirement to mirror every Host concept in the phone's main
navigation. Enforcing 1:1 in the runtime would conflict with existing desktop
workflows; making it the iOS default gives us the simpler experience without
migrating or restricting those workflows.

## Behaviour

- The main Console contains every Agent, keyed by Host and pane, with names
  before Space, directory and Host context. Pins and notification/share targets
  retain their existing identities. Names and Space labels are never routing keys.
- New Agent creates one Space and starts in its existing root pane. No extra
  shell tab is created. A blank directory resolves to the SSH account's actual
  home, not a currently focused terminal. Starting from another Agent inherits
  its directory but creates a separate Space.
- Advanced location options retain explicit Space reuse and linked Worktrees.
  A fresh Space at the same directory is not filesystem isolation; a linked
  Worktree remains the explicit isolated-checkout option.
- Spaces & Terminals remains a secondary browser. Existing Spaces, including
  ones without Agents, are neither hidden permanently nor deleted.
- Existing desktop multi-agent Spaces are not split, renamed or migrated.

## Lifecycle boundaries

Closing an Agent continues to call pane.close, never an additional
workspace.close or worktree.remove. The Host can close a Space when its last
pane closes and retains its existing worktree-group confirmation rules. This
UI change does not override those rules or introduce filesystem cleanup.
Renaming an Agent does not rename its Space. Space rename and Worktree removal
remain separate actions with their existing scope and confirmation.

The existing launch compensation only removes the resource created by that
launch after an explicit API rejection. Ambiguous transport outcomes retain
the remote resource rather than risking deletion of a successful launch.

This changes presentation and default creation, not SSH, attachment ownership,
notification identities or the Host protocol. It does not fix the separately
reported blank-terminal attach/display problem.
