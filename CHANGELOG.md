# Herden changelog

Herden retains its Heeler ancestry and the exact herdr commits merged into the
Host runtime. Upstream provenance is recorded in [UPSTREAM.md](UPSTREAM.md) and
[runtime/UPSTREAM.md](runtime/UPSTREAM.md).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Added a generic private gateway and reproducible Even Hub package workflow
  for an installed G2 beta. Deployment-specific Hosts and the exact HTTPS
  origin are injected only at build time; Host credentials remain server-side.
- Added an opt-in, Host-owned private-network HUD endpoint for the Even G2
  prototype. It serves bounded Agent-status SSE snapshots with 256-bit bearer
  credentials, deliberate credential retrieval/rotation, a Tailnet IPv4
  default, and read-only-by-default Send Enter/Interrupt controls; physical G2
  package, HTTP, background, and wake validation remains pending.
- Added a dictated `send_text` action to the Even G2 HUD command endpoint, so a
  spoken phrase can be typed into an Agent's prompt. It stays behind the same
  `--controls` opt-in, inserts without pressing Enter unless the caller asks
  for it, caps a phrase at 512 characters, and refuses control characters
  outright so a transcript can never carry a newline or escape sequence into a
  live terminal.

- The glasses now recognize `go to <number>`, `go back`, `dictate <text>`,
  and `close`. `Close` stops recording and darkens the display until the next
  head-up tilt.
  The explicit dictation voice command submits with Return when the phrase ends;
  the Host API's `send_text` default remains non-submitting.
- Added `page up` and `page down` voice navigation for both the Space list and
  open terminal output. A Space now opens on the newest physical display rows,
  with text wrapped using the G2 firmware font metrics; capped Host reads keep
  their newest lines instead of their oldest.

### Changed

- Codex agents launched or automatically resumed by Herden now use
  `FORCE_COLOR=1` on Linux and macOS, avoiding cached dark input-bar colours
  when the same session is viewed from a light terminal. This affects new
  Codex processes only and can be disabled with
  `[advanced] codex_force_color = false`.

- Fixed the glasses wake detector after a worn-device trace showed it remaining
  disarmed for seven minutes: resting IMU Y was about +0.03, while the former
  absolute gate required Y below -0.05. Wake now uses a relative head-up rise
  from the current resting pose. A marked up/right/left/down capture then proved
  that head-up is positive X, not Y; the detector now reads X with a +0.18
  relative margin and is regression-tested against the captured directions.
  Hub contextual-menu foreground events no longer
  shut down an active microphone session. Physical confirmation is still pending.
- The glasses voice endpointer now accepts quiet commands above a noisy worn-device
  microphone floor without treating initial ambient frames as a command. The
  microphone remains open for the next command and still closes each phrase
  after 1.2 seconds of silence.
- STT and Host reads/sends now have deadlines covering both the response and
  body; sleeping cancels an in-flight transcription. A refused mic-off is
  retried once and reported. Invalid startup-page results no longer trigger a
  blind rebuild that could disturb the display.
- Wake the Even G2 HUD only when measured pitch moves from a level pose to a
  head-up pose. Foreground, touch, and invalid IMU events cannot wake a dark
  lens. QR development sessions no longer hot-reload the phone app while it is
  being worn; rescan to load new source.
- Render the Even G2 HUD through one edge-to-edge native text container with
  zero padding and compact one-line chrome. This restores the firmware Unicode
  glyph set and removes full-screen image transfers. A bottom status line now
  shows microphone state and output position, Space rows use readable Agent
  names and plain WORK, QUESTION, DONE, and IDLE status labels without
  brackets or faux text columns. Opened Spaces follow their newest output. IMU/audio samples
  never repaint the lens, while meaningful voice and Host changes do. A timed-out
  display write cannot block voice processing or permanently wedge later updates.

- Clean the Even G2 HUD's Agent-output reader before it reaches the lens:
  remove terminal escapes, redraw residue, decorative ASCII, and coding-tool
  chrome while keeping readable replies, commands, and logs.

- The Host installer makes `herden` work in the current Terminal when it can:
  it links the command into a directory you own that is already on your PATH,
  such as Homebrew's. Otherwise its closing summary prints the one command that
  does it. The website's quick start is now a single line.

## [0.1.6] - 2026-09-18

### Added

- QR pairing now names the same local network or Tailscale/another VPN when
  the Host cannot be reached, so the iPhone's network check is explicit.
- Added distinct brand-colored pixel-letter marks for all 24 supported Agent
  kinds on Space and Agent rows. Plain terminals get a shell mark, with zsh,
  Bash or fish shown only when the Host reports that foreground shell.
- Added a saved Light/Dark switch to the public website header.
- Added saved-machine CLI routing, Letta and Cline detection, and terminal link resolution to the Host.
- Added Muse as a discoverable and launchable Agent kind, with recovery advice
  when an older Host rejects it.
- Added a public Even G2 development-status page with the working desktop demo,
  basic local instructions and clearly labelled demo and developer-package downloads.
- Added a one-tap Light/Dark switch to the Spaces list and to both terminal
  screens. The glyph shows the appearance the next tap gives, and the first tap
  out of System pins the opposite of what is on screen.
- Added Tab, Up and Down as permanent keys on the shared terminal keyboard, and
  a dedicated dictation-language key in place of the overflow menu.
- Added persistent one-tap terminal font-size controls to the shared Agent and Space keyboard.
- Added one-tap `/` and `$` shell-character keys to the shared terminal keyboard.
- Added a one-tap Alt+Up key to the shared Agent and Space keyboard for Codex question replies.

### Changed

- Replace the website's warm light background and demo-screen neutrals with cool
  grey, and refresh its privacy-safe iPhone and OpenGraph captures with the
  corrected terminal keyboard.
- Keep Herden in private beta while leaving the signed Host runtime, installer,
  privacy policy, licence attribution, and setup guide available at `herden.app`.
- Adopt Paper + Cobalt and the Live Tether identity across the iOS app and
  public site, including semantic Agent states, light/dark app chrome, the app
  icon, product marks, favicon and OpenGraph card.
- Kept the public site compact and terminal-styled, with smaller clickable AR
  glasses beside both phones and lens content based on the real glasses simulator.
- Lay the terminal keyboard out on one grid: Escape opens the first row and
  Backspace closes it with the four arrows as a single cluster between them, the
  four actions share the second row with a wide Return, and Tab joins the shell
  characters on the third. Every row spans the deck, and the overflow menu is
  gone rather than hiding keys behind an ellipsis.
- Give Agent and Space terminals the same top controls — Back, Light/Dark, font
  size, and message jump where a jump can go anywhere — and the same status row
  above the keyboard. A Space no longer carries a second navigation bar.
- Move terminal font size and the message-jump arrows out of the keyboard and
  off the terminal surface into those top controls, so neither covers output.

- Simplify the iOS terminal keyboard with repeating left/right arrows, Attach,
  Paste and clearly labelled Apple text dictation. Keep advanced keys under More.
- Optimize shared keyboard touch ergonomics by normalizing key height/widths on
  the fixed control rows, increasing Escape visibility and removing uneven
  spacing artifacts in the shell-character row.
- Record, review and attach compressed audio through the existing file upload
  flow, with cancellation and retry support and no automatic prompt submission.
  Insert only its uploaded path, leaving interpretation to the user or their
  Agent tooling.
- Make Dictate wider than the other attachment actions on the shared
  terminal keyboard.

### Fixed

- Restore hands-free Even G2 voice sessions: a head-up tilt wakes the dark lens
  and continuous microphone, adaptive silence ends each phrase, display SDK
  stalls no longer block commands, and 15 seconds of inactivity sleeps both.
  While the hardware path is stabilised, the spoken grammar is intentionally
  limited to `open <n>` and `go back`, and voice-state churn never repaints.

- Close the share sheet as soon as a shared file reaches the Agent, instead of
  stopping on a confirmation screen.
- Stop an iPhone from shrinking a desktop terminal while Herden is in the
  background. The phone releases its terminal when the app leaves the
  foreground, so the desktop gets its size back, and reattaches on return.
- Keep a Space and its shell pane after a managed Agent exits, and open that
  terminal on iPhone when the Agent row disappears. Ctrl-C can now return from
  Codex to the terminal without losing the Space, ready for a later resume. (#5)
- Keep Codex's retained dark input and question panels legible when a light desktop viewer
  connects to an Agent previously used from a dark terminal.
- Keep the last known Spaces visible but disabled while the app reconnects on
  foreground return, then replace them when the Host's fresh snapshot arrives.
- Terminal long-press copy now uses Ghostty's native Select All capture so its
  Copy All window includes shell scrollback and every available Agent screen
  line, even when the older lines were reached by scrolling.
- The terminal text window has one explicit Copy button. Selecting a passage
  changes it to Copy Selection, and the iOS text-edit Copy menu no longer appears.
- Clear Ghostty's terminal selection after opening the copy window and remove
  its separate terminal Copy popup.
- Keep action-key captions inside their keys on the shared iPhone terminal keyboard.
- Improved Host SSH bridge cleanup, reconnect handling, alternate-screen reads, terminal input, and observer recovery.
- Discover Agents installed through mise shims during non-interactive SSH probes.
- Freeze a shared terminal's application-facing palette once its child observes
  colour defaults or mode. A later phone or desktop viewer can no longer make a
  running Agent repaint retained cells for that viewer's Light/Dark scheme.
- Keep the last reported terminal palette and Light/Dark appearance while a new
  desktop client is still waiting for its terminal replies. An unreported
  client no longer clears application colour-query answers or makes Codex fall
  back to a light composer in a dark terminal.
- Follow the app's Light/Dark choice in the terminal itself, not just its
  chrome. The renderer resolves a palette from its own interface style, which a
  full-screen Space kept inheriting from the system, leaving a black terminal
  inside a light app.
- Make a whole Space row tappable instead of only the text drawn inside it.
  Terminal rows, which draw the fewest elements, were the hardest to hit.
- Let the Agent switcher take a tap on the first press rather than after
  several, by not letting its scroll view sit on each touch first.
- Stop covering a terminal with a Connecting dialog and a progress spinner on
  the way in. Connecting is how a terminal opens, not a condition to report; a
  failed terminal still gets its dialog and Reattach button.

- Resume Agents using their own terminal's client colour context, not the global
  foreground palette. Keep direct-attach input and resize working during the
  bounded observation wait, including client takeover.
- Start new terminals and Agent panes with neutral Host defaults. A client can
  establish its own palette after attaching without inheriting whichever desktop
  happened to be foreground when the terminal was created.

- Keep desktop colour observations within the currently controlled tab. Restore
  a same-tab desktop context after direct attachment, and select a remaining
  same-tab viewer when the desktop controller disconnects or deactivates.

- Keep iOS Light Mode theme choices light and Dark Mode choices dark; migrate
  incompatible saved choices while retaining valid selections.
- Default Host desktop chrome to the viewing terminal's palette. Preserve
  explicitly configured Host themes.
- Scope direct-attach colour reports to the controlled terminal and wait for
  refreshed defaults and queried palette entries before notifying the Agent.
  Application-painted RGB colours are not converted into client-relative colours.

- Treat Share Sheet uploads like in-app attachments: keep transfer state only
  while sharing, with no persistent Shared Files history in the app.
- Make Space rows open their Agent terminal again on compact iPhone layouts.
- Render the Fold at a legible home-screen size on a bright brand-green app
  icon instead of as a tiny dot on a black tile.

- Keep the iPhone's selected terminal background authoritative when Codex,
  Claude Code or another attached Agent cached a neutral light/dark panel from
  the persistent Host terminal.

- Open a newly created Agent on the first attempt instead of occasionally
  showing a blank terminal until the user leaves and re-enters it.

- Keep terminal themes local to each client when launching Agents. Opening an
  Agent from a light iPhone terminal no longer forces a white pane onto a dark
  desktop terminal. Older clients' launch palettes are accepted and ignored.

- Remove a Herden-launched Agent's dedicated pane and Space when its process
  exits, including exits initiated from the attached iPhone terminal.
- Follow Codex, Claude Code and pi session titles automatically while keeping
  a name explicitly set by the user authoritative.
- Close a sole-Agent Space as a unit and add an explicit Close Space action,
  so destructive exits no longer leave replacement shells behind on the Host.
- Shrink the terminal Pairing Code from roughly 77×39 to 49×25 cells while
  retaining the full Bootstrap Key, SSH Host fingerprint and connection data;
  the iOS app continues to decode legacy v1 codes.
- Configure the Host command on PATH in shell startup files without duplicate
  entries, and make `herden pair` work immediately after the quick-start block.

- Replace the outdated landing-page screenshot with a current Herden simulator
  capture showing the shared keyboard, media and document uploads, and dictation.
- Complete QR enrollment as soon as the iPhone's Device Key line arrives,
  without waiting for the SSH client to close its input stream.
- Point every landing-page TestFlight button to Herden's beta instead of Heeler's.
- Close the pairing QR code with q, Escape or Ctrl+C. Closing restores terminal
  settings and removes temporary pairing access.

### Added

- Add System, Light and Dark appearance modes across the app, with separate
  daylight and nighttime terminal themes for readable use outdoors.
- Synchronized the Host runtime with Herdr 0.9.0 and retained exact upstream
  ancestry through subtree merges.
- Added repo-local skills for repeatable herdr synchronization and selective
  Heeler change review.
- Show a compact, accent-colored `[herden]` label above Spaces in the terminal app.

- Unified the native iPhone console and Rust Host runtime as one Herden
  project, with built-in `herden pair` QR pairing over SSH.
- Added an agent-first iPhone workflow with horizontal navigation between the
  Agent terminal and the Spaces/Agents browser.
- Added one shared terminal keyboard for Agent and plain Space terminals,
  including cursor movement, vi keys, Ctrl-B, Ctrl-C, Escape, Return, paste,
  document and media upload, and on-device dictation.
- Added Traditional Chinese (Taiwan), Simplified Chinese, Swedish, Portuguese
  (Portugal), and English (US) dictation choices.
- Added native Share Sheet delivery of documents, images and video to an Agent,
  with durable transfer recovery and editable path insertion.
- Added friendly `user@hostname` Host labels while keeping network addresses as
  secondary connection details.
- Added optional encrypted Agent notifications through the Node plugin and
  stateless APNs relay.
- Added a checksum-verifying installer and release tooling for Linux and macOS
  Hosts.
- Added the static site at <https://herden.3loc.ltd> and the public TestFlight
  beta at <https://testflight.apple.com/join/nSsEZBvv>.

### Changed

- Clarify Herden's herdr and Heeler foundations, shared Space-first workflow,
  in-app file uploads and iOS Share Extension on the website and in the README.
  Explicitly credit Heeler for QR scanning, the original secure pairing flow
  and file-upload foundations, distinguishing Herden's integration and additions.

- Replace separate Space and Agent navigation with one Space-first Console on
  iPhone and in the Host terminal UI. Each Space now identifies its current
  Agent, Agent count, or ordinary terminal while the underlying Herdr
  workspace, tab and pane capabilities remain compatible. Pane split creation
  is no longer offered by the menu or default keyboard shortcuts.
- Replace the pixel-art shepherd and field illustrations with a clean,
  appearance-aware Fold mark across the app, Agent and Space rows, and website.
- Show Agents from every Host in one Console list, remove the Host filter, and
  identify each Host in the in-terminal Agent switcher.
- Highlight iOS sharing, media and document attachments, on-device dictation,
  and QR pairing across a tailnet on the landing page.
- Claude Code and Codex sessions start and restore with their native vi editor
  settings.
- Public commands, copy, state paths and sockets use the Herden name; legacy
  `HERDR_*` wire and environment identifiers remain where compatibility
  requires them.
- The combined project is distributed under Apache License 2.0, following the
  documented Apache-licensed herdr and Heeler baselines.
