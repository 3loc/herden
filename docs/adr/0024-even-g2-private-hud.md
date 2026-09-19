---
status: proposed
---

# Keep the Even G2 HUD inside the Host with a narrow private HTTP boundary

Herden's SSH transport remains the native iOS console transport. The optional
Even G2 HUD is a different, deliberately narrow surface: it projects Agent
status to an Even Hub application that runs inside the vendor's iPhone app.
The phone app owns its BLE connection to the glasses.

The Host owns an opt-in HTTP listener for one selected private address. Its
lifetime is a managed thread in the existing Host process, not a Node service,
reverse proxy, second daemon, cloud bridge, or replacement JSON API. Settings
and credentials are session-scoped below the existing Herden state directory.
The listener exposes health, authenticated full-snapshot SSE, and two
explicitly enabled commands: Send Enter and Interrupt. It never exposes a
terminal, filesystem, shell, or general RPC proxy.

Direct Tailnet HTTP is the preferred path when the installed Even runtime has
been proven to support it. A user can instead explicitly choose a private LAN
address. Neither path makes ordinary LAN HTTP encrypted. Tailnet membership
and source addresses do not replace bearer-token authentication.

The protocol version is independent of the Host's JSON API version. Status
snapshots deliberately omit terminal content and prompt text. Read-only is the
default, and server-side command rejection remains authoritative.

This decision is pending the physical-device gate: a packaged iPhone Even Hub
app must prove its HTTP/SSE, whitelist, installation, background and wake
behaviour on a paired G2 before Herden presents package generation or
always-available claims as a supported product workflow. Until then package
generation must fail clearly rather than produce a guessed `.ehpk` file.
