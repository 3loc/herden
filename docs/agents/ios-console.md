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
| `Console/ConsoleStore.swift`, `Console/HostConsoleProjection.swift` | Live Host inventory for operations and separate last-proven display rows during reconnect; snapshot-backed existing Space destination. |
| `Console/ConsoleAgent.swift`, `Console/AgentCardView.swift` | One row per Space, with occupant and attention ordering; Host + pane identity stays independent of display labels. |
| `Console/HarnessPixelMark.swift`, `Console/TerminalShellKind.swift` | Brand-colour pixel letters for Agents and foreground-shell detection for plain terminals. |
| `Console/AgentTerminalView.swift` | New Agent navigation from an attached Agent, after the launch sheet dismisses. |
| `Transport/Transport.swift`, `Transport/HerdenSSHTransport.swift` | New Space specification, remote home resolution and launch in the returned root pane. |
| `Terminal/SharedTerminalKeyboard.swift` | Shared arrow/attachment toolbar, Apple dictation and recording sheet for Agent and shell terminals. |
| `Terminal/TerminalScreenView.swift`, `Terminal/TerminalTextSelectionPresenter.swift` | Ghostty snapshot capture, one copy sheet, and suppression of the terminal's separate Copy popup. |
| `Dictation/HerdenAudioRecorder.swift` + `AudioRecordingSheet.swift` | Protected M4A capture, review, interruption handling and explicit file ownership transfer. |
| `Attachments/ComposerStagingStore.swift` | File upload and retries; recordings use the same path-only result as other files. |

New Agent flows through StartAgentStore to the transport, which creates a
Space and starts the Agent in its existing root pane; the refreshed snapshot
supplies the Host/pane destination. StartAgentView records that destination
before dismissing, then the presenting view yields once after dismissal before
opening the terminal surface.

On connection loss, HostConsoleProjection invalidates live Agents and
workspaces but keeps its last proven rows for display. ConsoleStore publishes
those collections separately; ConsoleView keeps Spaces visible and disables
each row until that Host is Connected and its fresh snapshot has landed. A
successful snapshot replaces the display copy, so a removed Space disappears
only after the Host has proved its absence. Never use display rows for RPCs,
subscriptions or Agent delivery.

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
- Capturing Ghostty selection with `select_all` alone leaves the native grid
  highlighted and can surface its own Copy popup behind Herden's text sheet.
  Use `copy_to_clipboard` with `selection-clear-on-copy` enabled, restore the
  clipboard before presenting the sheet, and keep the native terminal Copy
  responder/menu suppressed. The sheet's Copy button owns the actual user copy.

Regression coverage: `StartAgentStoreTests`, `TerminalAgentSwitcherTests`,
`ConsoleListPresentationStoreTests`, `ConsoleStoreTests`,
`AppForegroundRecoveryTests`, `TerminalAttachTests` and the new-Space launch
cases in `HerdenSSHTransportBehaviorE2ETests`. Run Swift validation on a Mac
through `make`; real-SSH cases need their fixtures and may skip locally.

Recording ownership passes synchronously only when staging accepts it. Sheet
teardown deletes unaccepted recordings; staging owns accepted files through
retry and cleanup. A terminal replacement dismisses the recorder, and upload
completion checks the original input generation before inserting the path.
