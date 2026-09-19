# Even G2 physical-device evidence

Status: **pending physical hardware validation**.

No result is recorded here until it is observed on a paired Even Realities G2
and an installed iPhone Even app. Simulator and CLI results do not satisfy this
gate.

| Requirement | Evidence required | Result |
| --- | --- | --- |
| Tailnet HTTP, SSE, authenticated read-only request | iOS/Even/SDK/firmware versions, exact host URL, steps and observation | Pending |
| Explicit LAN HTTP, SSE, authenticated request | Same, including ATS, local-network and WebView policy | Pending |
| Whitelist and install semantics | Omitted/empty/wildcard/IP/port/exact-origin behaviour; package/sideload requirements | Pending |
| Locked phone lifecycle | At least 30 minutes with known Agent transitions, near the end of trial | Pending |
| Wear, BLE and network recovery | Disconnect/reconnect and Wi-Fi/cellular observations | Pending |
| Glance/wake | Documented SDK/firmware call and physical observation | Pending |
| Idle battery | One-hour baseline comparison, brightness, network, wear state and update count | Pending |

Until all required rows have observed evidence, do not state that HTTP works in
the packaged Even app, that the HUD remains available in the background, that
an Agent transition wakes the lens, or that a reusable `.ehpk` can be built.
