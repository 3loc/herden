# iOS Console

The default is one new Agent per new backing Space, not a runtime constraint.
This is deliberate: Herden targets vibecoders who should not need to manage
terminals and Spaces separately before starting an Agent. Preserve existing
multi-agent Spaces. See [ADR 0020](../adr/0020-agent-first-ios-console.md).

## Map

Paths below are relative to `Sources/Herden/`.

| File | Responsibility |
| --- | --- |
| `Console/ConsoleView.swift` | Primary Agent list, New Agent, secondary Spaces & Terminals browser and navigation after sheet dismissal. |
| `Console/StartAgentView.swift` | Default automatic Space creation; explicit reuse and Worktree location options. |
| `Console/StartAgentStore.swift` | Launch destination policy, inherited directory and backing Space label. |
| `Console/ConsoleStore.swift`, `Console/HostConsoleProjection.swift` | Snapshot-backed existing Space destination: first Agent, otherwise first terminal. |
| `Console/ConsoleAgent.swift`, `Console/AgentCardView.swift` | Name-first presentation; Host + pane identity stays independent of display labels. |
| `Console/AgentTerminalView.swift` | New Agent navigation from an attached Agent, after the launch sheet dismisses. |
| `Transport/Transport.swift`, `Transport/HerdenSSHTransport.swift` | New Space specification, remote home resolution and launch in the returned root pane. |
| `Terminal/SharedTerminalKeyboard.swift` | One keyboard for Agent and shell terminals, including language and attachments. |

New Agent flows through StartAgentStore to the transport, which creates a
Space and starts the Agent in its existing root pane; the refreshed snapshot
supplies the Host/pane destination that opens after the creation sheet dismisses.

## Boundaries and failure modes

- A nil launch directory means the SSH account's home. A launch from another
  Agent inherits its directory, not its Space. Separate Spaces sharing a
  directory are not isolated checkouts; Worktree remains an explicit choice.
- Do not use Agent names or Space labels as routing keys, collapse Agents by
  Space, or create a new tab just because local navigation has no saved target.
- Close still uses `pane.close`. The Host can close the Space on its last pane
  and retains worktree-group confirmation. No extra workspace or file deletion
  belongs in this UI simplification.
- Launch acceptance does not prove the attached terminal rendered. For a blank
  cursor-only screen, check Agent readiness and remote pane content separately
  from the PTY attach/display path. The reported blank-terminal issue remains
  unverified; this navigation change is not evidence of a fix.

Regression coverage: `StartAgentStoreTests`, `TerminalAgentSwitcherTests`,
`ConsoleListPresentationStoreTests`, `ConsoleStoreTests` and the new-Space launch
cases in `HerdenSSHTransportBehaviorE2ETests`. Run Swift validation on a Mac
through `make`; real-SSH cases need their fixtures and may skip locally.
