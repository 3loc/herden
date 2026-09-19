# Even G2 HUD implementation report — 2026-09-12

## Implemented and checked

- The existing Herden Host starts a managed HUD supervisor with its normal
  headless server lifetime. It does not run Node, npm, Vite, a shell refresh,
  or a second service.
- `herden glasses enable`, `status`, `disable`, `token rotate`, read-only,
  controls, explicit bind/port, and reconfiguration handling are implemented.
  Settings and credentials belong to the selected Herden session. Credentials
  use 32 random bytes and a separate private, atomic credential file.
- First enable and deliberate rotation print the credential once for phone-side
  setup. Ordinary `status` output never displays it, while `token show` makes
  retrieval an explicit action.
- When a normal Tailscale interface has its paired IPv4 CGNAT and IPv6 ULA
  addresses, `herden glasses enable` selects the IPv4 address automatically.
  It asks for `--bind` only when multiple eligible Tailnet IPv4 addresses
  exist, or when the user prefers a LAN address.
- The listener accepts only an address assigned to the Host that is private
  LAN, Tailnet CGNAT, or IPv6 ULA. It rejects wildcard, public, and loopback
  binds. It limits request bodies and clients, authenticates SSE/commands with
  a timing-safe bearer comparison, sends bounded snapshot SSE, drops slow
  writers, and never exposes the Host JSON API, terminal contents, filesystem,
  or shell execution.
- The projection labels unavailable inventory stale/offline, uses opaque pane
  identifiers, detects additions/removals during one-second reconciliation,
  and suppresses initial/reconnect attention wake events. The Host only accepts
  Send Enter or Interrupt after controls are enabled, but the current lens does
  not bind either command.
- The Even renderer consumes HUD protocol v1 fields, removes public build-time
  credentials, serializes SDK updates, and does not cache a failed paint. Its
  lens list is Space-first: the Host resolves each `workspace_id` through
  `workspace.list`, never derives a Space name from a terminal title, Agent
  name, branch, or cwd. Each row is `host:kind:space:state`; `>` marks the
  selection. G2 navigation is deliberately small: scroll selects, click loads
  up to 1,000 lines of the selected Agent's recent output, scroll browses that
  reader, and double-click returns. A working TUI can expose only its visible
  screen through the Host API; idle Agents provide recent history. Attention
  updates never move an active selection. The current Even SDK has no
  font-size property, so the view uses a built-in Tamzen 7×14 bitmap terminal face
  across four image tiles rather than its fixed proportional font. The Hub
  converts neutral greyscale PNG tiles to the green G2 panel.
- TypeScript renderer tests and its production build passed on this checkout.
- `make glasses-test` and `make glasses-build` provide locked development
  verification for the Even source; customer packaging remains unavailable
  until the actual Even package workflow is proven.

## Not accepted as complete

The required physical iPhone/G2 milestone has not been run. Therefore the
following acceptance criteria are pending, rather than inferred from the
prototype or simulator:

- packaged-app Tailnet and LAN HTTP/SSE/authentication;
- Even network whitelist semantics and CORS origin requirements;
- `.ehpk` format, signing, installation and distribution workflow;
- 30-minute locked-phone, wear, BLE, cellular/Wi-Fi recovery and wake results;
- one-hour idle battery comparison.

`herden glasses package --output …` deliberately returns an actionable error
until these facts are measured. The old maintainer-specific deployment unit
was removed; the Node bridge remains only as a development fixture.

## Host test deployment

On 3loc, the pinned Zig 0.16.0 toolchain built the optimized Host and the
focused Glasses test selection passed nine tests. The executable was installed
atomically, then `herden server live-handoff --import-exe ~/.local/bin/herden`
preserved the running session. The installed and running executable hashes
match, `herden glasses enable` selected `100.64.0.2` automatically, and both
the v1 health response and an authenticated SSE connection were verified. A
follow-up live handoff installed the Space-first projection and bordered-card
renderer (`e42ec6d7afb547d7036a96ebb493c3d481f0ad09390f60b9dd943f16e3ee9c0b`);
an authenticated SSE frame was checked to contain the 3loc Space label
`glasses support`. This is a 3loc-only test build, not a public or fleet
release.

For desktop renderer development, the Vite-only proxy can read a local 0600
credential file and add the authorization header upstream. The simulator then
receives only a localhost proxy address and a non-secret placeholder; neither
the production bundle nor the Even manifest receives a credential or a guessed
network permission.
## Latest simulator evidence

Agneta's active Wayland desktop is running the updated native simulator through
a localhost-only SSH forward and Vite development proxy. The first screen is a
compact Space overview with a stable selection marker; it enters the read-only
status view only after a click. Current captures are
`/vm-share/screenshots/herden-glasses-list.png`,
`/vm-share/screenshots/herden-glasses-output.png`, and
`/vm-share/screenshots/herden-glasses-output-scrolled.png`.
A development `.ehpk` was generated at
`/vm-share/herden/herden-hud-output-reader.ehpk` (SHA-256
`91179b3f8666e5cd1be4914be82fc879d9dccbe8746e127ccecee968a60aefa5`); it is
not a hardware-verified or distributable package.
## Multi-Host development flow

The HUD client now stores a list of private Host endpoints. Its companion panel
shows connected Hosts and offers **Add a Host**, with the exact setup step:
run `herden glasses enable` on that machine and enter its private URL and
credential. The lens renders one dense row per Agent as
`host:agent:space:state`; this development session aggregates 3loc and
Fansvine. Each Host remains independently authenticated; this package is
read-only.
