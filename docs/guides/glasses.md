# Even G2 HUD

Herden has an optional Host-owned HUD endpoint for Even Realities G2 glasses.
It runs inside the existing Herden Host process and gives the phone-side Even
app a small Agent-status view. The Even app owns the Bluetooth link to the
glasses; Herden does not communicate with the glasses directly.

The feature is disabled by default. Direct use has no Herden cloud or
notification-relay requirement: it uses private-network HTTP between your
phone and Host. A private installed build may instead use the optional
self-hosted gateway in `glasses/gateway/` to combine several Hosts and
transcription behind one exact HTTPS origin while keeping every Host token on
the server. A Tailnet is preferred between the gateway and Hosts.

## Using the HUD

For development, run the Vite server and scan its current QR code with the Even
app on the phone paired to your G2. A private Even Hub beta can instead be
installed once and opened from the Hub without rescanning; its build injects
one operator-controlled HTTPS gateway origin. The phone must be able to reach
the chosen Host route and transcription service. Long-duration locked-phone,
recovery, and battery behaviour remain physical acceptance items below.

The glasses path is separate from iOS's SSH path. An iPhone can connect to a
Host over SSH while the glasses still report that Host as offline: the glasses
client uses the Host's token-authenticated HTTP bridge on port 8791, normally
through the Vite `/hud/<host>` proxy. Every Host selected in the glasses client
needs a reachable bridge and a matching token. Verify the route with `GET
/health` and an authenticated `/events` request before debugging Bluetooth or
voice. Bind the bridge to an address the phone can actually route to (a Tailnet
address when the phone has that Tailnet route, otherwise a private LAN address);
do not reuse a retired or unreachable address from an old QR session.

Some older Host installations predate the built-in `herden glasses` command.
Those deployments need the dependency-free bridge sidecar and a supervised
service, with its bind address, port, and token kept in the same operational
configuration as the Host. Upgrade the Host to a current public build when
possible; do not assume that an iOS SSH success proves the sidecar is running.

Once the app opens, the lens starts dark. Wear the glasses, lower your head to
a comfortable resting position, then tilt your head up to wake both the display
and microphone. The bottom row shows the microphone state and the last
recognised command. Speak normally: the microphone stays open while the lens
is lit, and a phrase is sent for transcription after about 1.2 seconds of
silence. You do not need to wake it again between commands.

| Say | Result |
| --- | --- |
| `open 2` or `go to 2` | Open the numbered Space shown in the list, at its newest available terminal output. Numbers one through twenty may also be spoken as words. |
| `go back` | Return to the Space list. |
| `page up` or `page down` | Move through the Space list or the open Space's output, whichever is visible. |
| `dictate <text>` | Type the words into the open Agent and press Return when the phrase ends. Requires Host controls to be enabled. |
| `close` | Stop recording and darken the lens. This must be a command on its own; `dictate close` sends the word as text. |

The list's printed numbers are the voice targets. They can change as Space
status changes, so read the current list before saying `open <number>`. In an
open Space, new output follows the bottom until you page up; page down to
return to the latest lines. After 15 seconds without a gesture or recognised
voice command, the lens and microphone close together. An active phrase or
transcription defers that idle close, but one lit session has a three-minute
safety cap. Tilt up again for a new session; touch and foreground events do not
wake a dark lens. A long press closes a lit session.

The G2 display is monochrome green. Software can vary brightness, not make the
lens white or blue. The native firmware chooses the text font and size.

For voice dictation, enable the Host write path explicitly:

```sh
herden glasses enable --reconfigure --controls
```

Without `--controls`, navigation and reading still work, but dictation is
refused. There is no general voice wake word: the head-up gesture starts the
listening session, and `close` ends it.

```sh
herden glasses enable
```

Herden selects the Tailnet IPv4 address by default, which works for the normal
IPv4/IPv6 pair assigned to one Tailnet interface. Choose an address explicitly
only when the Host has multiple eligible Tailnet IPv4 addresses, or to use LAN:

```sh
herden glasses enable --bind 192.168.1.20 --port 8791
```

Herden rejects wildcard, loopback, and public addresses. The HUD navigation is
read-only: scroll selects a Space, click opens its recent terminal output,
scroll browses that output, and double-click returns to the list.

Writing to an Agent is a separate, opt-in path behind `--controls`:

```sh
herden glasses enable --reconfigure --controls
```

Without that flag every `POST /command` is refused with `403
{"error":"controls are disabled"}`, whatever the request body says.

### `POST /command`

Token-authenticated, JSON in and JSON out. Three actions:

```json
{"action": "send_enter",  "agentId": "w1:pT"}
{"action": "interrupt",   "agentId": "w1:pT"}
{"action": "send_text",   "agentId": "w1:pT", "text": "run the tests", "submit": false}
```

Each maps to exactly one Host `pane.send_input` call against that pane:
`send_enter` sends `keys: ["enter"]`, `interrupt` sends `keys: ["ctrl+c"]`,
and `send_text` sends `{text}` — or, when `submit` is true,
`{text, keys: ["enter"]}` in that single call, so type-and-submit is atomic
and cannot interleave with another writer's input.

`submit` defaults to **false** for API callers. The glasses' explicit
`dictate <text>` voice command asks for `submit: true`: after the 1.2-second
silence endpoint, it types that text and Return atomically into the currently
open Agent. The recognized command is shown in the bottom lens status row.
The glasses also accept `go to <number>` and `go back` for navigation,
`page up` and `page down` to move through either the Space list or the open
Space's terminal output, and `close` to stop the microphone and darken the lens
until the next head-up tilt. Opening a Space starts at the newest output; the
Host keeps the latest text if an output read reaches its size cap.

`send_text` validates before it touches the socket:

- `text` is required. It is trimmed, and empty or whitespace-only text is a
  `400 {"error":"text is required"}`.
- At most **512 characters** after trimming, counted in characters rather than
  bytes so non-Latin dictation is not penalised. Longer is a
  `400 {"error":"text is too long"}`.
- **No control characters at all** — ordinary spaces are the only whitespace
  that survives. Newlines and carriage returns are *rejected, not converted*:
  the PTY reads either as Enter, so one embedded newline would submit a line
  despite `submit: false` and run everything after it as a further command.
  Rewriting them to spaces would silently change what the speaker said, which
  is worse than refusing. ESC is rejected because it opens an escape sequence,
  and tab because TUIs read it as completion. Violations are a
  `400 {"error":"text contains control characters"}`.

Shared with the other actions: an unknown action is a `400`, an `agentId` the
Host no longer lists is a `404 {"error":"agent no longer exists"}`, and an
identical repeat within 750 ms is a `409 {"error":"duplicate command
ignored"}`. For `send_text` "identical" means the same pane, the same `submit`
choice and the same text — a different phrase is a different intent and is
never rate-limited away.

A delivered command answers `200 {"delivered":true}`. A Host that refuses the
input answers `409 {"error":"command was not delivered"}`, and an unanswered
Host answers `503 {"error":"delivery uncertain; do not automatically retry"}` —
a write path must never retry itself into a doubled phrase.

The reader obtains up to 1,000 text lines when an Agent is idle. A working TUI
only exposes its visible screen through the Host API, so the HUD shows that
screen rather than inventing unavailable history.

The HUD uses one edge-to-edge native firmware text container with zero padding.
Even Hub exposes no font family, font size, or line height, so Herden gains
density by removing decorative chrome. Of ten measured firmware rows, one
names the Space, eight show Agent output, and the final row anchors microphone
state and output position. Opened Spaces start at the newest output and follow
it unless the wearer scrolls back. Native text preserves every Unicode glyph
the firmware supplies and avoids the four image transfers that previously
desynchronised the two displays. IMU and audio samples never repaint the lens;
only meaningful voice results, Host changes, and UI transitions do. Glyph
coverage varies with the firmware font.

On first enable, Herden prints the new bearer credential once so that you can
configure the phone-side client. `herden glasses status` never displays it.
Use `herden glasses token show` only when you deliberately need to retrieve it,
or `herden glasses token rotate` to invalidate existing event streams and print
a replacement. `herden glasses disable` removes the listener without affecting
Agents and retains the configuration for a future enable.

The endpoint supplies unauthenticated `GET /health`, token-authenticated
`GET /events` SSE snapshots, token-authenticated `GET /agent-output?agent=…`,
and the token-authenticated `POST /command` write path described above, which
stays closed until `--controls`. It does not provide a terminal, general
Herden RPC, shell execution, or filesystem access. Tokens are generated with 256 bits of randomness and saved
separately from configuration with private filesystem permissions.

## Current evidence boundary

On 21 September 2026, a private `.ehpk` built with SDK 0.0.15 was uploaded to
Even Hub, assigned to a beta tester, installed, and opened on a paired G2. Its
exact-origin HTTPS gateway delivered live multi-Host SSE and transcription.
This proves the private package/install route, but it is not a public-store
release and does not prove arbitrary user networks. `herden glasses package
--output …` still fails intentionally; private packaging is the explicit
`npm run pack:private` operator workflow documented in `glasses/README.md`.

Before claiming general availability, finish the remaining physical-device
milestone in `docs/research/even-g2-hardware-evidence.md`: direct Tailnet and
LAN behaviour, a 30-minute locked-phone transition trial, wear/BLE/network
recovery, repeatable wake behaviour, dictated-write capture, and a one-hour
idle battery comparison. Maintainer-specific DNS, TLS, and service units stay
in private operator configuration.
