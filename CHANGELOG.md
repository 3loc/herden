# Herden changelog

Herden retains its Heeler ancestry and the exact herdr commits merged into the
Host runtime. Upstream provenance is recorded in [UPSTREAM.md](UPSTREAM.md) and
[runtime/UPSTREAM.md](runtime/UPSTREAM.md).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Added a one-tap Light/Dark switch to the Spaces list and to both terminal
  screens. The glyph shows the appearance the next tap gives, and the first tap
  out of System pins the opposite of what is on screen.
- Added Tab, Up and Down as permanent keys on the shared terminal keyboard, and
  a dedicated dictation-language key in place of the overflow menu.
- Added persistent one-tap terminal font-size controls to the shared Agent and Space keyboard.
- Added one-tap `/` and `$` shell-character keys to the shared terminal keyboard.

### Changed

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

### Fixed

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

- Tell Agents to treat an attached audio recording as the user's spoken
  message instead of inserting an ambiguous file path as reference material.
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

- Remove completed shared files from the persistent top banner; retain their
  history under Shared Files in the menu.
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
