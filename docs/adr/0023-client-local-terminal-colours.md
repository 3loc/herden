---
status: accepted
---

# Keep terminal defaults local to each client

An Agent's persistent PTY can be viewed from a light iPhone and a dark desktop.
Launching it from either client must not pin that client's palette to the shared
terminal for the lifetime of the process.

The previous `agent.start.terminal_colors` implementation wrote OSC 10/11 before
executing the Agent in the same foreground job. The terminal correctly treated
those writes as explicit application colour overrides. Consequently, an Agent
launched from a light iPhone appeared as a white pane in a dark desktop client.

iOS themes now configure only the local Ghostty renderer. Agent launch requests
carry no theme. The Host keeps decoding the optional `terminal_colors` field for
older clients but ignores it, and launches the Agent without colour-setting
shell wrappers. Normal upstream terminal reports and query handling remain:
default-colour cells resolve in each attached client's terminal. Explicit colours
written by the running application remain application content.

Direct attach queries the viewing terminal's defaults, palette and appearance.
Replies are control metadata, never keyboard input. A mode report invalidates
the previous observation; publication waits for both fresh defaults and all
queried palette entries. The active attach owner can update only its terminal.
Defaults are applied before notifying a subscribed application, including a
palette change that retains the same light/dark mode. An old owner's disconnect
cannot clear a successor's context. Unsupported or incomplete observations do
not block typing and do not publish a fabricated palette.

The default Host chrome uses the `terminal` theme; explicitly selected Host
themes remain opt-ins. iOS limits each appearance's theme choices to matching
light or dark palettes and migrates incompatible saved choices.

The existing iOS Agent output filter remains a local heuristic: it rewrites
nearly neutral RGB backgrounds without changing the shared PTY. It cannot
identify semantic colours or guarantee contrast with explicit foregrounds.
This is not a complete solution for simultaneous light and dark viewers.

Desktop observations now apply only to the active controller's currently viewed
tab (including its popup), never every terminal when global foreground changes.
Direct attachment retains priority; its disconnect restores a valid same-tab
desktop controller or retains the last observation when none exists.

Pending Agent resumes now keep an ephemeral query context on their terminal,
separate from global desktop presentation. Each resume has its own bounded wait.
Direct attachment waits for the current owner's completed report, seeds query
answers before the child starts, and uses that owner's latest dimensions.
Explicit input can end only its target's wait; the fallback uses that terminal's
last observation or leaves unknown colours unanswered. Takeover transfers
ownership before old-client teardown, without an intermediate desktop resume.
No client palette is serialised into the session or written as an OSC override.

New workspaces, tabs, panes, layouts, popups, plugin panes and custom-command
terminals likewise start with neutral defaults. This matters because the iOS
transport starts `agent.start` before it can open the direct terminal stream;
there is no client palette to apply at that API boundary. The first attached
client then publishes its own defaults to the runtime.

Remaining work includes context for newly created terminals, colour context before
new Agent startup, and client-relative output or an explicitly selected
lossy presentation mode for applications that paint fixed RGB. The direct-attach
changes do not establish that those cases work.

An already-running TUI may have cached colours from the old launch wrapper.
Removing the wrapper prevents new contamination; it does not rewrite existing
Agent output or restart live work. Such an Agent may need to resume in a fresh
terminal after the fixed versions are installed.
