# Herden HUD prototype for Even Realities G2

`app/` is the Even Hub application source. It runs inside the Even phone app;
the G2 receives display updates through the vendor SDK. It is not a native
Herden iOS feature and does not own Bluetooth.

`bridge/` remains a development fixture for protocol and renderer work. It is
not a supported customer runtime. The supported direction is the managed Rust
endpoint in the Herden Host, configured with `herden glasses`.

For the current QR prototype's wake, voice, paging, dictation, and close
instructions, see [Using the glasses](../docs/guides/glasses.md#using-the-current-qr-prototype).

The app keeps the MVC boundaries small: `hud-model.ts` owns the projected
roster, selection, and view state; `hud.ts` formats lens content and
`lens-view.ts` owns the native firmware text container. `main.ts` is the
controller for Hub events, wake/sleep, and voice-command navigation. The
`host-service.ts`, `microphone-service.ts`, `stt.ts`, and `voice-pipeline.ts`
modules own their respective external I/O and asynchronous lifecycles. Tests
in `app/test/` exercise the model and service boundaries with fake SDK and
Host connections, as well as endpointing and ordered command delivery. STT
and Host requests share the bounded WebView operation helper in `deadline.ts`.

The app source has no maintainer endpoint, token, DNS record, TLS route, or
infrastructure dependency. Its network whitelist is deliberately empty until
the actual packaged iPhone permission semantics are observed on a paired G2.
Do not add a wildcard or a private deployment origin as a substitute for that
evidence.


## Developer commands

Run the portable checks from the repository root:

```sh
make glasses-test
make glasses-build
```

Machine-specific SSH aliases, tunnel routes, tokens, and simulator launchers
belong in private operator configuration, not this repository. The QR hardware
server disables Vite hot reload by default: rescanning deliberately loads new
source without silently resetting a worn microphone or lens. Set
`HERDEN_HUD_HMR=1` only for desktop-only iteration.

The HUD uses the G2 navigation path: `up`/`down` select a Space, `click`
opens it, and `double_click` returns to the list. A new session starts dark;
the calibrated head-up tilt wakes the lens and microphone together. While the
lens is lit the microphone listens continuously, keeps a short pre-roll, and
closes each phrase after measured silence. A long press sleeps the lens and
closes the microphone. The vendor
simulator's own debug strip is fixed and shows its complete event catalogue;
`glasses-input` exposes only the navigation gestures, and menu inputs are
ignored by the application.

The focused spoken grammar is `go to <n>` (also `open <n>` for compatibility),
`go back`, `page up`, `page down`, `dictate <text>`, and `close`. Paging moves
through the Space list or the open Space's terminal output, whichever is shown.
Opening a Space starts at the newest output; each physical lens row is measured
against the firmware font before the bottom page is chosen. `Close` stops recording and darkens
the display; the next head-up tilt starts a new listening session. A row number may be a digit or a word from
`one` through `twenty`. Dictation requires an open Space; after the 1.2-second
silence endpoint it sends the text and Return atomically to that Agent.
The recognized command stays in the bottom status row so a mishearing is visible.
Transcription is posted as WAV to a configurable base URL, `/stt` relative to
the app origin by default (the development server proxies it) and
`VITE_HERDEN_HUD_STT` otherwise. The glasses PCM format is an assumption — see
`PCM_FORMAT` in `app/src/audio.ts`.

The hardware HUD uses one native 576x288 firmware text container with zero
padding. The firmware owns the proportional face and its Unicode glyph set;
Even Hub exposes no font-family, font-size, or line-height control. Herden uses
readable one-line Space rows and a measured ten-row layout: one identity row,
eight selected-Agent output rows, and a microphone/status row at the bottom.
Opened Spaces start at the newest output and follow it while the wearer has not
scrolled back. IMU and microphone samples never repaint the lens; meaningful
voice results, Host changes, navigation, wake, and sleep do. Rendering is
last-frame-wins and bounded, so a missing SDK callback cannot block STT or
permanently wedge later text updates.

For renderer work that does not need hardware:

For public captures, start the development simulator with the URL
`http://localhost:5173/?demo=1`. This uses the real text renderer with generic
offline Spaces and sample output. It does not load saved Hosts, access tokens,
or make Host requests. Scroll, click and double click remain functional. The
demo is disabled in production builds.

```sh
cd glasses/app
npm test
npm run build
```

The Even CLI and simulator can help develop the display, but neither proves
packaged iPhone HTTP/SSE, package installation, locked-phone behaviour,
glance/wake, or battery impact. Record those physical-device findings in
`docs/research/even-g2-hardware-evidence.md` before enabling package delivery
or calling the HUD always available.

To point the desktop simulator at a private Host without adding a development
origin to the shipped manifest, run Vite with a local proxy:

```sh
cd glasses/app
herden glasses token show | sed -n '$p' > ~/.config/herden/glasses-simulator-token
chmod 600 ~/.config/herden/glasses-simulator-token
HERDEN_HUD_PROXY_TARGET=http://192.168.1.20:8791 \
HERDEN_HUD_PROXY_TOKEN_FILE=~/.config/herden/glasses-simulator-token \
VITE_HERDEN_HUD_PROXY=1 npm run dev -- --host 127.0.0.1
npm run sim
```

With `VITE_HERDEN_HUD_PROXY=1`, the simulator starts connected through the
local proxy. The real credential stays in the Vite process and is never
included in the web bundle, panel, or production configuration. The proxy
exists only in Vite; it does not change production CORS or Even network
permissions.
