# Herden

Unified Herden product: a Rust Host runtime for persistent coding agents and a
native iOS agent console over SSH. The Host runtime began from pristine
upstream herdr 0.8.2; public commands, state paths, and product copy are Herden.
Read `CONTEXT.md` for vocabulary and `docs/adr/` before challenging
architecture decisions—the transport design in particular was reached after
eliminating several dead ends.

## Architecture

- **Stack**: SwiftUI, iOS 18+, iPhone. SSH via the repository-local `Packages/HerdenSSH` (libssh2 + OpenSSL), terminal rendering via the pinned libghostty-spm `GhosttyTerminal` product. See ADR 0001 (native stack), ADR 0003 (the superseded Dictation-era target raise), and ADR 0004 (terminal engine).
- **Host runtime**: `runtime/` builds the `herden` executable. Runtime state is
  rooted at `~/.config/herden`; `herden pair` owns Pairing and renders the QR
  code without a plugin or Node prerequisite. See ADR 0017.
- **Transport**: the Host's JSON API (NDJSON over a remote Unix socket) reached through OpenSSH direct-streamlocal channels onto the socket itself — no socat. A server that denies stream-local forwarding fails preflight rather than falling back. Interactive terminals request a PTY and exec `herden agent attach` on it. See ADR 0011, which supersedes ADR 0002.
- The UI layer must depend on a transport abstraction (protocol), never on an SSH library's types directly.
- Sibling deliverables live in this repo: `plugin/` is the optional Host
  notification extension (Node, zero framework, `npm test`); `relay/` is the
  stateless Push Relay it posts to (dependency-free Node, `npm test`);
  `landing/` is the zero-JS site at `herden.3loc.ltd`. Production deployment
  configuration lives outside this repository. Wire types in
  `Sources/Herden/Transport/Generated/` are produced by
  `scripts/generate-wire-types.py` from the committed compatibility schema
  snapshot `scripts/herdr-schema.json`; regenerate with
  `--schema scripts/herdr-schema.json` rather than hand-editing them. The
  vectors in `plugin/test-vectors/` are consumed by both Node and Swift suites;
  change them in lockstep.

### Map

| Path | Responsibility |
| --- | --- |
| `docs/agents/ios-console.md` | Agent-first navigation/creation map and Space compatibility boundaries (ADR 0020). |
| `Sources/Herden/Terminal/SharedTerminalKeyboard.swift` | The single Agent/Space control deck, including dictation, language selection, attachments and Paste. |
| `Sources/Herden/Transport/SSHTransportSettings.swift` | Host command defaults and injectable SSH environment boundaries. |
| `Sources/Herden/Sharing/` | Durable Share Extension transfer ingestion and delivery. |
| `runtime/` | Rust Herden Host, CLI and built-in `herden pair`. |
| `runtime/src/pairing/code.rs` + `Sources/Herden/Pairing/PairingCode.swift` | Paired Host/iOS codecs for compact v2 and legacy v1 pairing envelopes. |
| `plugin/test-vectors/pairing-code-v2.json` | Cross-language source of truth for the v2 pairing wire format. |
| `plugin/` | Optional Node notification extension. |
| `relay/` | Stateless APNs relay. |
| `landing/` | Static Herden site and public installer copy. |
| `install.sh` | Verified Host download and shell PATH setup; mirrored exactly at `landing/public/install.sh`. |
| `scripts/test-install-docker.sh` | Debian shell PATH matrix and Alpine published-binary installer checks. |
| `docs/guides/install-host.md` | Public Host setup and current-terminal PATH requirements. |
| `Makefile` | Local build, test, Host release and TestFlight entrypoints. |
| `docs/guides/releasing-host.md` | Four-platform build validation, public publication and fleet audit; shared Zig build-output hazards. |
| `scripts/run-ci-ios-tests.sh` | Exhaustive local iOS and real-SSH validation runner. |
| `UPSTREAM.md` | Heeler/herdr provenance and update policy. |
| `.agents/skills/herden-testflight/` | TestFlight source verification, build/upload, beta review and invitations. |

Both Agent and Space terminal views feed the shared keyboard into the same
terminal input controller; attachment paths and pasted text therefore reach
the live PTY through one guarded input path.

Pairing facts flow from the Host codec into a Base45 QR envelope and through
the shared vector into the Swift decoder tests; change all three in lockstep.

The installer persists PATH in shell startup files; the quick-start export
updates the current Terminal. Keep both: a `curl ... | sh` child cannot update
its parent shell's environment. Installer changes run through
`bash scripts/test-install-docker.sh`; see the Host guide for shell coverage.

## Load-bearing Host facts

Rediscovering these is expensive. Versioned observations below refer to the
upstream herdr runtime from which Herden Host was derived. Keep legacy
`HERDR_*` environment and wire identifiers unless a migration is explicitly
designed; they are compatibility surfaces, not public branding.

- The herdr API socket serves **one request per connection** (read one line, write one line, close). Only `events.subscribe` keeps the connection open. Plan channel usage accordingly. (Re-verified live on 0.8.0: a second write on a served connection gets `EPIPE`. `pane.graphics.stream`, previously listed here, does not exist in the 0.8.0 schema — graphics methods are `pane.graphics.set`/`clear`/`info`, all one-shot.)
- Wire format: request `{"id": "<any string>", "method": "...", "params": {...}}` + `\n`; `params` is required, and `{}` satisfies it. Success `{"id", "result"}`, failure `{"id", "error": {"code", "message"}}` (both re-verified live on 0.8.0), subscription event lines `{"event", "data"}` with no id.
- The first message on any new connection path should be `ping` — it returns the server protocol version (0.8.2 answers `{"version":"0.8.2","protocol":20,...}`; 0.8.0, verified live, answered `{"version":"0.8.0","protocol":19,...}`). herdr's API has no stability guarantee; parse leniently (ignore unknown fields). The app enforces a **floor**, not equality: `HerdenSSHTransport.minimumProtocolVersion` refuses older servers, `generatedProtocolVersion` only drives an advisory notice. Equality here made every 0.8.0 Host unusable (#140) — do not restore it.
- The API schema is exported offline via `herden api schema --json` (JSON Schema 2020-12). Its `$ref` paths are non-standard nested (`#/schemas/request/$defs/X`) — preprocess before feeding codegen tools. The committed 0.8.2 snapshot declares 91 request methods and 26 event kinds, and every one of those kinds has a typed `EventData` variant; separately, 3 pane-scoped kinds (`pane.output_matched`, `pane.agent_status_changed`, `pane.scroll_changed`) have typed `SubscriptionEventData`. Payloads herdr actually emits are still worth verifying empirically.
- Pane ids are opaque strings. Protocol-20 `scripts/herdr-schema.json` declares `pane_id` as a string with no `pattern`. Observed herdr 0.7.5 captures (`w1:pA`, `w3:pB`, `wV:p1`) and live 0.8.0 `agent.list` samples (`w1:pT`, `w1C:p1`, `wR:pC`, `wV:p1H`) are alphanumeric `w…:p…` identifiers and include uppercase letters. Those captures contain no tmux-style `%N`; that does not prove herdr can never emit it. Treat every pane id as an opaque string; do not parse or validate a grammar.
- SSH exec channels are session channels, capped by sshd's `MaxSessions` (default 10) per connection. All RPC traffic must go through a request queue that bounds concurrency.
- `herden agent attach` requires a TTY (ratatui). It works over an exec channel only when a PTY is requested.
- herdr 0.7.5 tightened `agent.start` (verified against a live 0.7.5 server): the kind must be on its supported-agent list (arbitrary commands like `bash -i` are rejected with `unsupported interactive agent kind`), and a freshly created pane is rejected with `agent_pane_busy` ("not an available shell") until its shell reaches the interactive prompt — a few seconds. The transport retries on that code; see `SSHTransport.startAgentAwaitingShell`. On 0.8.0 `agent.start` is asynchronous instead: it returns `launch_pending: true` immediately (verified live 6ms after pane creation) and `agent_pane_busy` no longer occurs — the retry path stays as harmless 0.7.5 compat.
- Default remote socket: `~/.config/herden/herden.sock`; named sessions live
  under `~/.config/herden/sessions/<name>/herden.sock`. Resolve `$HOME` over
  exec once per Host. Run that probe explicitly through `/bin/sh`; login shells
  such as Nushell do not share POSIX expansion syntax.
- If the Herden Host is not running, connecting to the socket fails outright; there is no auto-start on the socket path. Fallback: run a Herden Host CLI command over exec (verify auto-spawn behavior — open question).
- `herden agent attach` resolves its target against **agents only**: attaching a plain shell pane fails with `agent_not_found` (verified against a live 0.7.5 server; resolution unchanged in the 0.8.2 source). Ordinary terminals attach with `herden terminal attach <terminal_id> [--takeover]` instead (0.8.2, verified against the installed CLI and the `v0.8.2` source tag): after resolving the Agent's `terminal_id`, `agent attach` enters this exact same client path (`src/cli/agent.rs` → `run_terminal_attach`). It targets a **terminal id** (from e.g. `tab.create`'s root pane), speaks the client socket derived from `HERDR_SOCKET_PATH` by inserting `-client` before `.sock` — distinct from both the JSON API socket and `remote-client-bridge` — supports raw input, resize, and takeover, allows **one writable attach owner per terminal** (a second attach without `--takeover` is refused; takeover displaces the previous owner), and is Unix-only in the inspected source (`#[cfg(unix)]`). Run it over exec with a PTY, as with `agent attach` — the 0.8.2 client puts the real terminal into raw mode. Interacting with a shell pane over the JSON API still means `pane.send_text`/`pane.send_keys` plus `pane.read`. Note `pane_output_changed` is emitted but **not subscribable** (0.8.0: the one emitted kind missing from the `Subscription` oneOf), so there is no output-change push — see the read/refresh facts below.
- `pane.send_text` types into any pane's PTY; a trailing `\n` presses Enter and the shell executes the line (verified live). `tab.create`/`workspace.create` accept `cwd`, `env`, and `label`, and `workspace.create` already returns a root pane running the user's shell — a plain terminal pane needs no `agent.start`.
- Reading pane content, verified live on 0.8.0: `pane.read`/`agent.read` take `source: visible|recent|recent_unwrapped` plus `lines` — **no offset or cursor**, so remote history is not addressable. `recent` defaults to 80 lines; the server caps every read at **1000 lines**. For alternate-screen TUIs (claude), history is capturable **only while the agent is idle**: `agent.read` fails `agent_not_idle` while working, and `pane.read` silently degrades to the visible screen while reporting `truncated: false` — use `agent.read` whenever depth matters. `read.revision` is always 0, never a change signal. The text lives at `result.read.text` (nested), not top-level.
- Output-change signals, verified live on 0.8.0: `pane.output_matched` is edge-triggered — one push when the visible buffer's match predicate flips no-match→match (plus one at subscribe time if already matching), silence during sustained output — useless as a change feed. `pane.agent_status_changed` is the precise push signal (two ~125-byte events per prompt round trip). `pane.updated` remains a ~4/s noise source. `events.wait` implements only pane agent-status matches despite the schema declaring 19 `EventMatch` variants, and its param is `match_event` (a single object).
- `agent.prompt`, verified live on 0.8.0: types the text **and Enter** (auto-submits); without `wait` it returns `agent_prompted` immediately — a delivery ack, nothing more. `wait.until` must include `done`: claude finishes on `done`, not `idle`, so idle-only waits reliably time out. Prompting a **working** agent is accepted unconditionally; queueing happens inside the agent TUI (verified for claude), not in herdr. `target` accepts pane ids and agent names, not agent-session UUIDs.
- `pane.send_input {pane_id, text?, keys?}` (verified live on 0.8.0) inserts without submitting when `keys` is omitted; `{text, keys: ["enter"]}` is an atomic type-and-submit. Key-name parsing is shared with `send_keys` and laxer than 0.7.4: `enter`/`esc`/`ctrl+c`/`C-c` accepted case-insensitively, `ctrl-c` still rejected with `invalid_key`.
- Malformed requests are answered with `id: ""` instead of the request id (verified live on 0.8.0) — id-keyed response matching needs a fallback or such requests pend forever. `ping` on 0.8.0 also reports `capabilities` (`live_handoff`, `detached_server_daemon`).
- Starting claude in a cwd absent from `~/.claude.json` blocks on an in-TUI trust dialog herdr cannot dismiss (hit live on 0.8.0) — a fresh-directory agent launch can wedge before its first prompt.
- Rename methods, verified against a live 0.7.5 server: `agent.rename` enforces `^[a-z][a-z0-9_-]{0,31}$` (`invalid_agent_name` otherwise) and clears the custom name when `name` is null or omitted; `workspace.rename` accepts **any** label (empty, whitespace, 500 chars). The `pane_updated` event a rename fires does **not** carry the agent name, and `pane.updated` fires on every terminal-title change (34 events in 6s measured live) — do not use it as a resync trigger; renames surface via post-RPC resync instead.
- herdr 0.7.5 **replays recently buffered events on `events.subscribe`** (verified live; 0.7.4 replayed nothing). Still no state replay — initial sync stays snapshot-based; treat replayed events as ordinary change signals.
- `events.subscribe` is **all-or-nothing**: one pane-scoped entry naming a dead pane fails the entire request with `pane_not_found` (re-verified live on 0.8.0, including alongside a valid global entry; the error id is `<requestID>:sub:<index>:probe`, so it does not correlate with the request id). Pane-scoped subscriptions are snapshot-derived and must never outlive the connection they were taken on, or a single exited pane wedges the Host offline forever — see `EventsSession.dropPaneSubscriptions`.
- Scrolling an attached terminal's history depends on the **agent CLI**, not on herdr, and the CLI's own history is the only copy. Captured from a pty and from live panes on 0.8.2: `herden terminal attach` always emits `?1049h` and toggles mouse reporting on then off, leaving whatever the inner application asks for. Claude Code, codex, and grok all set `?1049h` plus `?1000/1002/1003/1006h`, so `TerminalTouchScroll.remoteScrollSequence` sends real SGR wheel reports and all three scroll. Verified live against a Claude pane: six wheel-up reports moved its viewport and made it draw its own `Jump to bottom (click) ↓` affordance. **Measure `claude` in a trusted directory** — in an untrusted cwd it blocks on the trust dialog, emits ~1.2 KB, and sets neither alt screen nor mouse tracking, which reads as a capability difference that does not exist.
- An alternate-screen agent leaves **no herdr-side scrollback**: a live Claude pane reports `max_offset_from_bottom: 0`, and `pane.read`/`agent.read` return only the viewport (49 rows) however many lines are asked for. A plain shell pane on the same server returns 304 of 400 requested. So an app cannot recover an agent's history through the API; the only way back through it is to scroll the CLI itself, and `TerminalScrollControl.canScrollRemoteContent` reports whether that is possible at all.
- `herden remote-client-bridge` bridges stdin/stdout to the **client socket** (the TUI client/server protocol for `herden --remote`), not the API socket — verified against herdr 0.7.5 source (`src/remote/unix.rs`, `run_remote_client_bridge`); no API-socket stdio bridge exists in 0.7.5. Its "ensure server running" side effect is why it works as the wake command.

## Conventions

- All builds, Swift tests, device installs, archives, and TestFlight uploads run on macOS; never attempt them from a Linux checkout. They all go through `make` (see `make help`). An interim TestFlight build is `make bump && make testflight` — App Store Connect rejects reused build numbers.
- Keep validation scoped to the changed product surface. Runtime-only work uses
  `make host-build`, `make host-test-one FILTER=…`, or `make host-test` and must
  not build iOS. App-only work uses `make ios-build-sim`,
  `make ios-test-one SUITE=…`, or `make ios-test`; add `make ios-test-ssh` only for changes under
  `Packages/HerdenSSH`. Use `make test-all` only when a change crosses Host and
  iOS boundaries or as a release check. These targets use stable per-machine
  Cargo and Xcode caches so task worktrees do not rebuild dependencies.
- Cutting a release is `make publish` (`scripts/publish.sh`, documented in `docs/guides/releasing.md`): it cuts `CHANGELOG.md`'s `[Unreleased]`, bumps `MARKETING_VERSION` in `project.yml`, builds and uploads to TestFlight, then tags and creates the GitHub release. `CHANGELOG.md` is the source of both the version and the notes; never hand-edit `MARKETING_VERSION` or create a `vX.Y.Z` tag by hand. Preview with `make publish DRY_RUN=1`.
- Every distributable Host build is one public-to-fleet operation: publish the new versioned binaries and checksums, update both root `install.sh` and its identical `landing/public/install.sh` copy to download that exact version, and deploy them to `https://herden.3loc.ltd` before any fleet rollout. Test the public URL—not local files—in disposable Linux containers for fresh installation, an idempotent repeat, and upgrade from the previous release; verify the installed version and checksum against the published metadata.
- After those public checks pass, run the 3loc/fleet rollout from the `3loc` VM and make every reachable `herden_hosts` member install through that same published `https://herden.3loc.ltd/install.sh`. The release path must not build or distribute `SOURCE=`, `REF=`, snapshots, or controller-local binaries; if the fleet target still does so, update its playbook before rollout. Finish with the fleet's independent version/checksum audit and report offline Hosts as pending. The Host release is not complete until the landing-page installer, its downloaded binaries, and the reachable fleet all agree.
- A single suite runs with `xcodebuild test -project Herden.xcodeproj -scheme Herden -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:HerdenTests/<SuiteTypeName>`; `make test` runs everything. The `Packages/HerdenSSH` package suites are a separate test plan run by `scripts/run-herdenssh-package-tests.sh` — changes under `Packages/HerdenSSH` need that runner, not `-only-testing:HerdenTests/...`.
- The committed `Herden.xcodeproj` must stay in sync with `project.yml`, so run `make generate` and commit the regenerated project alongside every YAML change. GitHub Actions are intentionally absent: builds and releases run locally. `scripts/run-ci-ios-tests.sh` remains the exhaustive local validation runner; it provisions disposable sshd instances and asserts executed test counts for the real-SSH suites. The remaining locally gated suites skip cleanly on machines without a local sshd and seeded key.

- Swift 6 strict concurrency. No force unwraps or `try!` outside tests.
- Private keys never leave the Keychain and are generated on device (CryptoKit Ed25519) where possible. Per-Host Notification Keys are symmetric keys: the app retains each one in the shared Keychain and copies it over SSH to that Host so the plugin can encrypt notifications. Host key policy is TOFU with fingerprint confirmation.
- Pin libssh2 and OpenSSL exactly in `Packages/HerdenSSH` and review both the source hashes and the committed XCFramework checksums before updating; normal builds consume the checked-in artifacts.
- Pin libghostty-spm exactly and review both its Swift sources and prebuilt XCFramework checksum before updating.
- Tracker is GitHub issues in this repo (`gh issue ...`). Reference issues from commits with `refs #<n>`.
- User-visible changes get a `CHANGELOG.md` entry under Unreleased, referencing the PR; internal refactors and test work stay out of it.
- Update `CONTEXT.md` when domain terms change; add an ADR only for hard-to-reverse, surprising trade-offs.

## Agent skills

### TestFlight

Use `.agents/skills/herden-testflight/SKILL.md` for the source-to-archive-to-beta-review
workflow. An upload does not submit a build for review, and a newer device install
can share an older upload's build number; compare source before selecting a build.

### Issue tracker

Issues live in this repo's GitHub Issues (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles map 1:1 to repo labels. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
