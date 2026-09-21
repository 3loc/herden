---
status: accepted
---

# Keep the Even G2 HUD inside the Host with a narrow private HTTP boundary

Herden's SSH transport remains the native iOS console transport. The optional
Even G2 HUD is a different, deliberately narrow surface: it projects Agent
status to an Even Hub application that runs inside the vendor's iPhone app.
The phone app owns its BLE connection to the glasses.

The Host owns an opt-in HTTP listener for one selected private address. Its
lifetime is a managed thread in the existing Host process, not a required Node
service, cloud bridge, or replacement JSON API. Settings
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

An optional self-hosted gateway may combine several of these narrow Host
endpoints and transcription behind one exact HTTPS origin for an installed
private build. It holds the Host credentials, strips client token parameters,
and does not store audio. This is operator infrastructure, not a Herden cloud.

A packaged private beta proved exact-origin HTTPS, SSE, transcription, upload,
tester assignment, installation, and launch on a paired G2 on 21 September
2026. Long-duration background, recovery, wake, dictation, and battery gates
remain before any general-availability claim. The Host CLI must continue to
fail clearly instead of implying it can produce a public package; private
operators use the explicit package workflow in `glasses/README.md`.
