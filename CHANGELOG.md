# Herden changelog

Herden's public history begins with one consolidated source release. Earlier
development commits remain private; upstream provenance is recorded in
[UPSTREAM.md](UPSTREAM.md) and [runtime/UPSTREAM.md](runtime/UPSTREAM.md).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- Replace the outdated landing-page screenshot with a current Herden simulator
  capture showing the shared keyboard, media and document uploads, and dictation.
- Complete QR enrollment as soon as the iPhone's Device Key line arrives,
  without waiting for the SSH client to close its input stream.
- Point every landing-page TestFlight button to Herden's beta instead of Heeler's.
- Close the pairing QR code with q, Escape or Ctrl+C. Closing restores terminal
  settings and removes temporary pairing access.

### Added

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

- Highlight iOS sharing, media and document attachments, on-device dictation,
  and QR pairing across a tailnet on the landing page.
- Claude Code and Codex sessions start and restore with their native vi editor
  settings.
- Public commands, copy, state paths and sockets use the Herden name; legacy
  `HERDR_*` wire and environment identifiers remain where compatibility
  requires them.
- The combined project is distributed under Apache License 2.0, following the
  documented Apache-licensed herdr and Heeler baselines.
