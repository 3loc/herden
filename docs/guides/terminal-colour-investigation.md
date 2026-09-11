# Client-owned terminal colours

Research and design recommendation, 11 September 2026. No implementation or
deployment is claimed by this document.

## Conclusion

The viewing client should own its default foreground, background and palette.
Herden Host should preserve that choice, not stamp an iPhone or desktop theme
onto a shared Agent. But there is no universal “no theme” switch across terminal
applications. A renderer always needs colours, and applications can explicitly
paint their own colours.

The exact goal has two parts:

1. A light iPhone must not turn a dark desktop terminal white.
2. The Agent UI on each device must remain readable and match that device's mode.

Default-colour output can satisfy both. Arbitrary explicit RGB output cannot
satisfy both faithfully when the devices show the same running process.
Achieving both for supported Agents requires client-relative application output,
not just forwarding a light/dark flag. For arbitrary applications, a guaranteed
uniform display requires a deliberately lossy rendering mode.

## The actual chain

```text
Codex / Claude
    ↕ application terminal bytes and query replies
Host's virtual terminal, backed by libghostty-vt
    ↕ rendered terminal output and attach input
herden terminal attach over an SSH PTY
    ↕ SSH bytes
iPhone's embedded Ghostty → pixels

The desktop is another viewer of the Host, not another mandatory layer
between the iPhone and the Agent.
```

Linux PTYs provide a bidirectional terminal interface. They do not choose a
light or dark palette. SSH carries the terminal data. The emulator interprets
it. A multiplexer such as herdr is also an emulator, so queries can terminate
there instead of reaching the screen the user is looking at.
[Linux PTY manual](https://www.man7.org/linux/man-pages/man7/pty.7.html).

| Application output | Meaning | Can each viewer resolve it differently? |
| --- | --- | --- |
| SGR `39` / `49` | Use default foreground / background | Yes, if defaults remain symbolic through the Host |
| ANSI red, blue, etc. | Use an indexed palette entry | Yes, provided the index is preserved and the palette is not overridden |
| SGR `38;2;r;g;b` / `48;2;r;g;b` | Use this exact RGB foreground / background | Not without changing the requested colour |
| OSC `10` / `11` with a colour | Change terminal default foreground / background | Changes emulator state; not the same as selecting a cell's default |
| OSC `10;?` / `11;?` | Ask what the defaults are | Supplies information; it does not set colours |

SGR `0` resets text attributes, not the configured terminal theme. OSC `110`
and `111` reset dynamic foreground/background overrides, but do not convert
already explicit RGB cells into default-colour cells. Palette entry “black”
is not synonymous with default background, especially in light mode.
[xterm controls](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html),
[Ghostty dynamic colours](https://ghostty.org/docs/vt/osc/1x),
[Ghostty resets](https://ghostty.org/docs/vt/osc/11x).

## What herdr already offers

For its own terminal interface, the appropriate setting is:

```toml
[theme]
name = "terminal"
auto_switch = false
```

This follows the outer terminal's ANSI palette instead of imposing a named
RGB theme. Existing custom colour overrides still need review. `auto_switch`
is for switching herdr's named themes; it is not required for symbolic colours
to follow the viewing palette. `terminal` retains coloured accents and selected
rows, so it means terminal-relative, not monochrome.
[herdr configuration](https://herdr.dev/docs/configuration/#theme).

Read-only inspection of this VM found `rose-pine-dawn` with auto-switch disabled
in `~/.config/herden/config.toml`. That is a fixed light UI choice. It is not
evidence about other fleet machines, nor proof that every Agent's white area
comes from that setting. No configuration was changed.

Source findings in the current Herden worktree:

- `runtime/src/app/state.rs`, `Palette::terminal`: main text and panel
  backgrounds use `Color::Reset`; accents and some surfaces use ANSI colours.
- `runtime/src/pane/terminal.rs`, `ghostty_default_fg/bg` and
  `PaletteOverrides`: ordinary defaults and unmodified palette indices can
  remain client-relative. Child-defined palette overrides become explicit RGB.
- `runtime/src/client/mod.rs`, around line 446: outer-theme queries are enabled
  only when `state.attach_escape.is_none()`. Direct attach does not query them.
- `runtime/src/client/terminal_setup.rs`: direct attach disables the client
  protocol setup that subscribes to light/dark reports.
- `runtime/src/server/headless.rs`, `ClientShellHostTheme`: reports are accepted
  only for `ClientShell`, not `TerminalAttach`.
- `runtime/src/app/theme_sync.rs`: accepted foreground-client defaults and
  appearance are applied across all terminal runtimes. This is not a
  per-terminal appearance-owner design.

Consequently, changing the Host UI setting alone does not make iOS appearance
reach Codex or Claude. The imported upstream path needs a targeted extension.
The inspected newer upstream source has the same relevant attach/theme logic;
an upstream refresh alone does not supply that extension.

## Ghostty, kitty and mode reporting

Keep a real light/dark palette at the final renderer. Ghostty supports paired
themes, for example `theme = dark:Catppuccin Frappe,light:Catppuccin Latte`.
Kitty can select `dark-theme.auto.conf`, `light-theme.auto.conf` and
`no-preference-theme.auto.conf` from the desktop's appearance. These are local
renderer choices, not remote application settings.
[Ghostty themes](https://ghostty.org/docs/features/theme),
[kitty themes](https://sw.kovidgoyal.net/kitty/kittens/themes/).

The modern reporting protocol separates a query (`CSI ?996n`), a dark/light
reply (`CSI ?997;1n` or `CSI ?997;2n`) and subscription (`CSI ?2031h`). A report
announces a change; it cannot recolour an application's existing RGB output.
Each emulator boundary and the application must support the relevant handling.
[Protocol specification](https://contour-terminal.org/vt-extensions/color-palette-update-notifications/).

Our pinned libghostty-spm UIKit wrapper already calls both surface and
controller colour-scheme APIs from `updateColorScheme()`. It is incorrect to
conclude that iOS never informs Ghostty just because our view calls `setTheme`.
The missing Host direct-attach path is separate.

Herden's `TerminalThemeSettings` also intentionally allows a dark-only theme
in the light-mode slot. Strict “Light means light throughout” must remove that
contradiction or explicitly present it as an override. Mode reports and actual
selected palette must agree, not blindly report light for a dark surface.

## Codex and Claude are different

Claude's official documentation offers automatic light/dark selection through
`/theme`, and ANSI-based presets and custom themes. Auto needs a truthful
terminal report reaching Claude. ANSI tokens are promising for client-relative
output, but the documentation does not prove every panel, foreground and diff
uses defaults. That needs captured-output and contrast checks before promising
full compatibility.
[Claude terminal configuration](https://code.claude.com/docs/en/terminal-config#match-the-color-theme).

Codex's `/theme` controls syntax highlighting, not the entire UI background.
[Official Codex command documentation](https://learn.chatgpt.com/docs/developer-commands?surface=cli).
In the source matching installed Codex 0.153.2:

- `codex-rs/tui/src/terminal_palette.rs` caches the startup default-colour probe.
- `codex-rs/tui/src/tui.rs` seeds that cache at Unix startup. The inspected code
  does not provide the required live light/dark refresh path.
- `codex-rs/tui/src/style.rs` blends a message-panel colour from that background
  and emits RGB or indexed output according to terminal capabilities.

Therefore fixing reports in Herden is necessary but insufficient for existing
Codex sessions. A narrow Codex change should refresh cached colours, derived
styles and redraw on mode changes. For simultaneous mixed-mode viewers, even
that is insufficient: panels and mode-dependent foregrounds must use
client-relative styling instead of fixed RGB. Historical rendered content also
needs consideration, not only the next prompt.

`NO_COLOR` is an application convention, not a universal terminal enforcement
switch. Supporting programs can suppress colours; overrides may take precedence.
It does not assign a light palette and should not be presented as a complete
solution for interactive Agents. Changing `TERM` to lie about capabilities is
also not a colour-ownership design.
[NO_COLOR specification](https://no-color.org/).

## Assessment of our existing fixes

Removing the launch-time OSC 10/11 wrapper is correct. The current worktree no
longer sends iOS launch colours; Host decoding retains the legacy field but
ignores it. This prevents one particular source of shared palette contamination.
It does not repair cached colours inside running applications. Deployment
receipts say the iOS change shipped in build 26; the pending Host source change
has not been established as deployed by this investigation.

`AgentTerminalThemeAuthorityFilter` is a workaround, not a colour protocol.
It rewrites semicolon-form truecolour backgrounds whose RGB channels differ
by at most eight into SGR `49`. It does not adapt explicit foregrounds,
indexed backgrounds, tinted panels or colon-form RGB. It cannot know whether a
grey background is decorative or meaningful. Its comment promising preservation
of semantic backgrounds is stronger than its implementation can justify.
Changing a background without its foreground can itself reduce contrast.

## Recommended implementation, not yet performed

1. Keep the selected palette local. Use a genuine light/dark pair on iOS and
   terminal-relative Herden desktop chrome. Do not inject launch OSC setters.
2. Extend direct attach to negotiate and update client appearance/defaults as
   control metadata. Keep query replies separate from keyboard input. Bound and
   correlate queries so a late reply cannot be typed into a shell.
3. Scope reported state to a terminal and its authorised active controller,
   not every pane on the Host. Define detach, takeover and headless defaults.
   Make metadata available before a new Agent's startup probe, not only after
   launch. Never let an unrelated viewer recolour another Agent's query state.
4. Preserve default and palette-index cells in rendering. Notify subscribed
   applications of changes, but never promise a notification rewrites RGB.
5. Make supported Agent output client-relative. Validate Claude's ANSI/default
   options; contribute the smallest necessary Codex theme/cache changes upstream.
   Do not silently rewrite global Agent preferences or restart live work.
6. Replace the grey-background heuristic only with a verified policy. If exact
   mode uniformity is required for unsupported arbitrary TUIs, offer an explicit
   local monochrome/normalised mode. It necessarily sacrifices colour fidelity
   and must preserve non-colour distinctions such as selection and diff signs.

Items 1–4 provide sound ownership and adaptive single-viewer behaviour. They
are not a substitute for item 5 when a light phone and dark desktop must both
display the same Agent correctly. No claim of the full product outcome should
be made until that mixed-client case passes.

## Acceptance gates for a subsequent implementation

Test Codex and Claude, ordinary shells, new and resumed Agents, light-to-dark
and dark-to-light transitions, attach/detach/reconnect, takeover and headless
startup. Cover both Agent and Space terminal views.

Use a light iPhone and dark Ghostty/kitty desktop viewing the same persistent
Agent. Neither viewer may change the other's defaults. Both must retain readable
body text, prompts, selections, permissions, code and diffs. Test explicitly
coloured foreground/background pairs and OSC overrides, not only neutral panels.

Capture startup queries, replies and change notifications at each boundary;
assert terminal-scoped ownership and that late replies never become user input.
Verify default/indexed/RGB cell identity independently of screenshots. Include
packet-split sequences, absent reporting support, old clients and old Hosts.
Contrast checks and screenshots must cover the actual selected palettes.

These are future validation gates. This investigation was read-only against
applications and services; it did not run that end-to-end matrix.

## Evidence scope

- Herden source: `43f9d36ee881bf2b94eb2efad4770a1b08ba6371` plus existing dirty
  work, including the launch-colour removal. Installed local Host: 0.9.3.
- herdr cache: `61ca85d5895bb530b59da85beeccdd767f4720d2`; relevant paths compared
  against imported `425c8617`.
- Codex: installed 0.153.2, source tag `rust-v0.153.2`; compared relevant cache
  and styling code with `02a8f038b87ad34d4a1dc5058eda26972ed7aa6c`.
- Claude: installed 2.1.267; behaviour claims based on official documentation,
  not private implementation or an automated UI test.
- iOS wrapper: exact project pin `356f730bec03281fc7b83666a129b0246137ea26`,
  inspected using `git show`, not the cache's newer default branch.

Next action: implement the scoped ownership and Agent-compatibility work above
as a separately authorised change. Do not deploy configuration-only changes and
claim they solve the entire chain.
