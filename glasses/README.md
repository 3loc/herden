# Herden HUD prototype for Even Realities G2

`app/` is the Even Hub application source. It runs inside the Even phone app;
the G2 receives display updates through the vendor SDK. It is not a native
Herden iOS feature and does not own Bluetooth.

`bridge/` remains a development fixture for protocol and renderer work. It is
not a supported customer runtime. The supported direction is the managed Rust
endpoint in the Herden Host, configured with `herden glasses`.

The app source has no maintainer endpoint, token, DNS record, TLS route, or
infrastructure dependency. Its network whitelist is deliberately empty until
the actual packaged iPhone permission semantics are observed on a paired G2.
Do not add a wildcard or a private deployment origin as a substitute for that
evidence.


## Developer commands

From the repository root, the current two-Host Agneta development setup is
managed by Make:

```sh
  make glasses-agneta      # one command: sync, replace, and open on Agneta
  make glasses-mbair       # one command: sync, replace, and open on mbair
make glasses-open        # replace any tracked simulator and show a fresh one
make glasses-status      # tunnels, Vite, and simulator process state
make glasses-screenshot  # /vm-share/screenshots/herden-glasses-latest.png
make glasses-input GLASSES_INPUT=down
make glasses-input GLASSES_INPUT=click
make glasses-input GLASSES_INPUT=double_click
make glasses-stop
```

`make glasses-open` checks its tracked process tree first and replaces it, so
it does not accumulate invisible simulator windows. Override the desktop host
with `GLASSES_DEV_HOST=<ssh-host>` when needed.

The HUD uses the G2 navigation path: `up`/`down` select a Space, `click`
opens it, and `double_click` returns to the list. A long press is push to
talk: it opens the glasses microphone, the release transcribes the clip and
the lens shows both the transcript and what it resolved to. The vendor
simulator's own debug strip is fixed and shows its complete event catalogue;
`glasses-input` exposes only the navigation gestures, and menu inputs are
ignored by the application.

Spoken commands: `open <n>` / `open space <n>` / bare `<n>` opens the Space at
that visible row (digits or `one`..`twenty`), `go back` / `back` / `close`
returns to the list, and `dictate <text>` parses but reports that the
read-only HUD endpoint has no Host write path yet. Transcription is posted as
WAV to a configurable base URL, `/stt` relative to the app origin by default
(the development server proxies it) and `VITE_HERDEN_HUD_STT` otherwise. The
glasses PCM format is an assumption — see `PCM_FORMAT` in `app/src/audio.ts`.

The HUD has its own compact Tamzen 7×14 bitmap terminal face. Even's native text API
does not expose a font family, font size, or line height, so four image tiles
cover the lens and give the compact old-terminal treatment without relying on
the phone's proportional system font. The Hub converts neutral greyscale PNG
tiles to the G2's green 4-bit display. The simulator's `/api/screenshot/glasses`
endpoint currently renders image frames as a solid green block; use
`make glasses-screenshot` for the actual simulator-window capture.

For renderer work that does not need hardware:

For public captures, start the development simulator with the URL
`http://localhost:5173/?demo=1`. This uses the real Tamzen renderer with generic
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
HERDEN_HUD_PROXY_TARGET=http://100.64.0.2:8791 \
HERDEN_HUD_PROXY_TOKEN_FILE=~/.config/herden/glasses-simulator-token \
VITE_HERDEN_HUD_PROXY=1 npm run dev -- --host 127.0.0.1
npm run sim
```

With `VITE_HERDEN_HUD_PROXY=1`, the simulator starts connected through the
local proxy. The real credential stays in the Vite process and is never
included in the web bundle, panel, or production configuration. The proxy
exists only in Vite; it does not change production CORS or Even network
permissions.
