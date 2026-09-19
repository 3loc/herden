# Even G2 HUD (hardware gate pending)

Herden has an optional Host-owned HUD endpoint for Even Realities G2 glasses.
It runs inside the existing Herden Host process and gives the phone-side Even
app a small Agent-status view. The Even app owns the Bluetooth link to the
glasses; Herden does not communicate with the glasses directly.

The feature is disabled by default. It has no Herden cloud, notification relay,
Node runtime, reverse proxy, DNS record, certificate, or service-unit
requirement. It uses private-network HTTP between your phone and Host. A
Tailnet is preferred when available. A LAN address is also supported, but LAN
HTTP is not encrypted.

```sh
herden glasses enable
```

Herden selects the Tailnet IPv4 address by default, which works for the normal
IPv4/IPv6 pair assigned to one Tailnet interface. Choose an address explicitly
only when the Host has multiple eligible Tailnet IPv4 addresses, or to use LAN:

```sh
herden glasses enable --bind 192.168.1.20 --port 8791
```

Herden rejects wildcard, loopback, and public addresses. The HUD package is
currently read-only: scroll selects a Space, click opens its recent terminal
output, scroll browses that output, and double-click returns to the list. It
does not send input to an Agent. The Host can reserve its narrow command
endpoint with `--controls`, but the current package deliberately does not bind
it until that path has hardware evidence.

The reader obtains up to 1,000 text lines when an Agent is idle. A working TUI
only exposes its visible screen through the Host API, so the HUD shows that
screen rather than inventing unavailable history.

The HUD uses an embedded Tamzen 7×14 bitmap terminal face rendered as four image
tiles. This is deliberate: the Even native text surface has no supported font
family, font-size, or line-height setting. The SDK converts neutral greyscale
tiles to the G2's 4-bit green panel. This rendering choice has simulator
coverage but still needs physical G2 legibility evidence.

On first enable, Herden prints the new bearer credential once so that you can
configure the phone-side client. `herden glasses status` never displays it.
Use `herden glasses token show` only when you deliberately need to retrieve it,
or `herden glasses token rotate` to invalidate existing event streams and print
a replacement. `herden glasses disable` removes the listener without affecting
Agents and retains the configuration for a future enable.

The endpoint supplies unauthenticated `GET /health`, token-authenticated
`GET /events` SSE snapshots, token-authenticated `GET /agent-output?agent=…`,
and a command endpoint reserved for a future hardware-validated control path.
It does not provide a terminal, general Herden RPC, shell execution, or
filesystem access. Tokens are generated with 256 bits of randomness and saved
separately from configuration with private filesystem permissions.

## Current evidence boundary

This code is not yet a finished G2 product workflow. No physical G2 evidence
has been recorded for packaged iPhone HTTP/SSE, the production network
whitelist, package format/install route, locked-phone background operation,
or display wake. `herden glasses package --output …` therefore fails
intentionally instead of assembling an unverified package. The prototype's
maintainer-specific DNS, TLS, and systemd instructions are not product setup
instructions and must not be used for a release.

Before this guide can describe installation as available, run and record the
physical-device milestone in `docs/research/even-g2-hardware-evidence.md`:
versions, Tailnet and LAN HTTP fetch/SSE/auth tests, whitelist and install
semantics, a 30-minute locked-phone transition trial, wear/BLE/network
recovery, wake behaviour, and a one-hour idle battery comparison.
