---
tags: [release, host-0.9.6, terminal-colour-context, fleet]
category: release
related: [terminal-colour-investigation, host-095-release]
---

# Herden Host 0.9.6 — deployed

Source `7552e6519b841815c8c7e14d79530f4f101bbaee`, tag `host-v0.9.6`.
The release contains the client-owned terminal-context resume and neutral
terminal creation fixes. Four-platform assets, installer, metadata, and
landing site were published from the same source state.

Linux Host validation: 3,398 passed, zero failures, four ignored. Public
installer fresh, repeat, 0.9.5 upgrade, and `herden update` checks passed on
amd64 and arm64. The 11 reachable fleet Hosts now report 0.9.6 with matching
public checksums; Kalibrio and T14 remain offline, and Wagneta remains excluded
by boot identity. The existing iOS 0.1.5 build 27 remains current on Tedda,
Vivian, and TestFlight; no iOS source changed, so no redundant upload was made.

Evidence: `/vm-share/software/herden/host-v0.9.6/`.

The broader explicit-RGB application rendering requirement remains unresolved;
this release does not rewrite Agent configuration or restart live Agents.
