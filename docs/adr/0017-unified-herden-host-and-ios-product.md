---
status: accepted
---

# Ship the Host runtime and iOS app as one Herden product

Herden owns both the Host runtime and the iOS client in this repository. The
Host starts from a pristine upstream herdr 0.8.2 source snapshot, recorded in
`runtime/UPSTREAM.md`, rather than from 3LOC's customized herdr checkout. Its
public executable, commands, state directory, sockets, documentation, and
release assets use the Herden name.

Pairing is a security-sensitive Host capability, not an optional plugin action.
The Host therefore exposes `herden pair` and a hidden, forced-command enrollment
path directly in Rust. The command creates a short-lived restricted Bootstrap
Key, prints a terminal QR code, enrolls exactly one iOS Device Key, and cleans
up temporary authorization on success, expiry, interruption, or error. The
existing `HERDR-PAIR:1`, `HERDR-ENROLL:*`, and `HERDR_*` identifiers remain on
the wire or in the environment where changing them would break deployed apps.

The Node plugin remains only as the optional notification and Live Activity
extension. It is not required to pair or use the core product. The public
installation path installs one `herden` binary and may install that extension
when Node and git are present.

This supersedes ADR 0007's decision to implement Pairing through a plugin. It
does not alter ADR 0011's SSH direct-streamlocal transport: the iOS app still
talks directly to the Host over SSH, with no Herden account service or
application backend in the data path.
