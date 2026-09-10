# Herden changelog

Herden retains its Heeler ancestry and the exact herdr commits merged into the
Host runtime. Upstream provenance is recorded in [UPSTREAM.md](UPSTREAM.md) and
[runtime/UPSTREAM.md](runtime/UPSTREAM.md).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- Make Space rows open their Agent terminal again on compact iPhone layouts.
- Render the Fold at a legible home-screen size on a bright brand-green app
  icon instead of as a tiny dot on a black tile.

- Keep the iPhone's selected terminal background authoritative when Codex,
  Claude Code or another attached Agent cached a neutral light/dark panel from
  the persistent Host terminal.

- Open a newly created Agent on the first attempt instead of occasionally
  showing a blank terminal until the user leaves and re-enters it.

- Fresh Agents now keep the active iPhone terminal palette for the lifetime of
  their managed launch, so Codex and other colour-aware TUIs cannot cache the
  Host's restored dark palette before startup.

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
