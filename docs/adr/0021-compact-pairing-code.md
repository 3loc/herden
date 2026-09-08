---
status: accepted
---

# Encode Pairing Codes compactly without weakening Pairing

The Host emits `HERDR-PAIR:2`, a compact binary payload rendered as Base45.
The full 32-byte Bootstrap Key seed, 32-byte SSH Host fingerprint digest,
absolute expiry, port, username, Host name, and every candidate address remain
inside the code. IPv4 and IPv6 candidates use their binary representation;
DNS names and user-facing strings remain length-prefixed UTF-8. Base45 keeps
the entire printable envelope in QR alphanumeric mode.

The terminal renderer uses QR error-correction level L and a four-module quiet
zone. Error correction affects resistance to a damaged image, not credential
strength; a clean, high-contrast terminal is the intended surface. A
representative full payload renders in 49 columns by 25 rows instead of the
previous approximately 77 by 39. The iOS decoder continues accepting the JSON
and base64url `HERDR-PAIR:1` envelope so existing codes do not regress.

This remains a self-contained, local pairing ceremony. A shorter server-held
reference could produce a smaller QR, but would add another state lookup and
network protocol before the phone has established trust. Removing addresses,
shortening key material, or truncating the Host fingerprint was rejected
because those choices would reduce reachability or security rather than merely
encoding the same facts efficiently.
