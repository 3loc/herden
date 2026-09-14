# iOS Console

The Console has one Space list. Each row describes its current Agent or ordinary
terminal; those are not separate navigation hierarchies. The default remains
one primary terminal per new Space, not a runtime constraint. Preserve existing
multi-agent Spaces. See [ADR 0022](../adr/0022-unified-space-first-console.md).

## Map

Paths below are relative to `Sources/Herden/`.

| File | Responsibility |
| --- | --- |
| `Console/ConsoleView.swift` | Primary Space list, Agent/Terminal creation and navigation after sheet dismissal. |
| `Console/StartAgentView.swift` | Default automatic Space creation, explicit reuse and Worktree options, plus the ordered success handoff used by both presentation sites. |
| `Console/StartAgentStore.swift` | Launch destination policy, inherited directory and backing Space label. |
| `Console/ConsoleStore.swift`, `Console/HostConsoleProjection.swift` | Snapshot-backed existing Space destination: first Agent, otherwise first terminal. |
| `Console/ConsoleAgent.swift`, `Console/AgentCardView.swift` | Name-first presentation; Host + pane identity stays independent of display labels. |
| `Console/AgentTerminalView.swift` | New Agent navigation from an attached Agent, after the launch sheet dismisses. |
| `Transport/Transport.swift`, `Transport/HerdenSSHTransport.swift` | New Space specification, remote home resolution and launch in the returned root pane. |
| `Terminal/SharedTerminalKeyboard.swift` | Shared arrow/attachment toolbar, Apple dictation and recording sheet for Agent and shell terminals. |
| `Dictation/HerdenAudioRecorder.swift` + `AudioRecordingSheet.swift` | Protected M4A capture, review, interruption handling and explicit file ownership transfer. |
| `Attachments/ComposerStagingStore.swift` | File upload and retries; accepted recordings enter the existing SFTP path. |

New Agent flows through StartAgentStore to the transport, which creates a
Space and starts the Agent in its existing root pane; the refreshed snapshot
supplies the Host/pane destination. StartAgentView records that destination
before dismissing, then the presenting view yields once after dismissal before
opening the terminal surface.

## Boundaries and failure modes

- A nil launch directory means the SSH account's home. A launch from another
  Agent inherits its directory, not its Space. Separate Spaces sharing a
  directory are not isolated checkouts; Worktree remains an explicit choice.
- Do not use Agent names or Space labels as routing keys, collapse Agents by
  Space, or create a new tab just because local navigation has no saved target.
- Close still uses `pane.close`. The Host can close the Space on its last pane
  and retains worktree-group confirmation. No extra workspace or file deletion
  belongs in this UI simplification.
- Never call `dismiss()` before recording the started Agent ID, and never build
  its terminal in the sheet teardown transaction. Either race can produce a
  blank first-open surface that appears after leaving and re-entering; keep the
  ordering in `StartAgentPresentationTransition` covered by tests.

Regression coverage: `StartAgentStoreTests`, `TerminalAgentSwitcherTests`,
`ConsoleListPresentationStoreTests`, `ConsoleStoreTests` and the new-Space launch
cases in `HerdenSSHTransportBehaviorE2ETests`. Run Swift validation on a Mac
through `make`; real-SSH cases need their fixtures and may skip locally.

Recording ownership passes synchronously only when staging accepts it. Sheet
teardown deletes unaccepted recordings; staging owns accepted files through
retry and cleanup. A terminal replacement dismisses the recorder, and upload
completion checks the original input generation before inserting the path.
