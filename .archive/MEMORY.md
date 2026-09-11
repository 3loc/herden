# Project Archive

## Design

- [2026-09-11 — Terminal colour ownership: herdr, Ghostty/kitty, Codex and Claude](2026-09-11/terminal-colour-investigation.md)
- [2026-09-10 — Fold logo, website, and Tedda deployment](2026-09-10/fold-logo-and-tedda-deployment.md)

## Release

- [2026-09-11: Host 0.9.5 per-tab desktop colour isolation published and rolled out; iOS 27 unchanged; deployment reverified 12:35 UTC](2026-09-11/host-095-desktop-colour-release.md)
- [2026-09-11: Host 0.9.4 published and rolled to eleven reachable Hosts; iOS 27 reverified](2026-09-11/host-094-public-fleet-release.md)
- [2026-09-11: Build 27 on both phones and TestFlight; Host 0.9.4 pending](2026-09-11/master-build27-host094-checkpoint.md)
- [2026-09-11 — Correct Heeler QR/pairing/upload attribution with feature provenance](2026-09-11/feature-provenance-correction.md)
- [2026-09-11 — Website: upstream positioning, Space-first workflow and iOS file sharing](2026-09-11/site-positioning.md)
- [2026-09-11 — TestFlight build 26: latest sharing and client-colour fixes](2026-09-11/testflight-build-26.md)
- [2026-09-11 — Client-colour fix installed and verified on Tedda](2026-09-11/tedda-client-colours-deployment.md)
- [2026-09-10 — Website PATH activation guidance](2026-09-10/site-path-activation-guidance.md)
- [2026-09-10 — Complete master release: iOS build 24 and Host 0.9.3 audit](2026-09-10/complete-master-release-build24.md)
- [2026-09-10 — Release build-time optimization](2026-09-10/release-build-time-optimization.md)
- [2026-09-10 — Space-first Host 0.9.3 release](2026-09-10/space-first-host-093-release.md)
- [2026-09-10 — Build 23 redeploy and Host 0.9.2 release](2026-09-10/redeploy-build23-host092-checkpoint.md)
- [2026-09-10 — TestFlight build 22 with Fold identity](2026-09-10/testflight-build-22.md)
- [2026-09-09 — TestFlight build 21 and tedda deployment](2026-09-09/testflight-build-21.md)
- [2026-09-08 — Compact pairing QR, Host 0.9.1 and iOS build 20](2026-09-08/compact-pairing-qr-release.md)
- [2026-09-08 — TestFlight privacy metadata and own-Host review instructions](2026-09-08/testflight-review-metadata.md)
- [2026-09-08 — Host 0.9.0, public/fleet alignment and TestFlight build 19](2026-09-08/release-alignment-0.9.0-build19.md)
- [2026-09-08 — Public Host 0.8.3 branding and legacy-session installer hotfix](2026-09-08/public-host-0.8.3-branding-hotfix.md)
- [2026-09-08 — TestFlight build 18 and repo-local submission skill](2026-09-08/testflight-build-18.md)
- [2026-09-08 — Latest paid-team build deployed to Tedda](2026-09-08/latest-paid-team-tedda-deployment.md)
- [2026-09-08 — Apache publication readiness and tedda deployment](2026-09-08/apache-publication-readiness.md)
- [2026-09-08 — Tedda clipboard build installed and launch verified](2026-09-08/tedda-clipboard-install.md)

## Infrastructure

- [2026-09-08 — Fleet-wide enrollment-fixed Herden Host rollout](2026-09-08/fleet-host-runtime-rollout.md)

## Debugging

- [2026-09-11: Terminal-scoped resume query context; 3,397 Linux tests pass; uncommitted and not deployed](2026-09-11/terminal-resume-query-context.md)
- [2026-09-11 — Completed shared document banner fixed and deployed to Tedda](2026-09-11/completed-shared-file-banner.md)
- [2026-09-11 — Client-local terminal colours; remove shared launch palette](2026-09-11/client-local-terminal-colours.md)
- [2026-09-10 — Herdr upstream sync through 425c8617](2026-09-10/herdr-upstream-sync-425c8617.md)
- [2026-09-10 — P0 Space navigation and app-icon repair, build 25](2026-09-10/p0-space-navigation-icon-build25.md)
- [2026-09-10 — Terminal theme authority for existing Agents](2026-09-10/terminal-theme-authority-existing-agents.md)
- [2026-09-09 — Codex light terminal startup](2026-09-09/codex-light-terminal-startup.md)
- [2026-09-08 — Installer shell PATH setup and Docker validation](2026-09-08/installer-shell-path.md)
- [2026-09-08 — Recover tedda's Hosts across the retired app identity](2026-09-08/tedda-host-catalog-recovery.md)
- [2026-09-08 — Attach restored Hosts through live legacy herdr sockets](2026-09-08/legacy-herdr-socket-compatibility.md)

## Feature

- [2026-09-08 — Compact [herden] terminal sidebar identity](2026-09-08/terminal-sidebar-branding.md)

- [2026-09-08: Agent-first iOS Console and tedda deployment](2026-09-08/agent-first-ios-console.md)

- [2026-09-07 — Native sharing, Host identity, and console edge navigation](2026-09-07/native-sharing-host-identity-console-navigation.md)
- [2026-09-08 — Share the exact Agent control deck with Space terminals and remember Agent defaults](2026-09-08/space-keyboard-agent-defaults.md)

- [2026-09-08 — Pairing QR close keys and terminal cleanup](2026-09-08/pairing-close-keys.md)
## 2026-09-11 — Host 0.9.6 release

Published `host-v0.9.6` from `7552e6519b841815c8c7e14d79530f4f101bbaee`. The
release fixed per-terminal resume context and neutral creation defaults, then
passed 3,398 Linux tests and public installer checks on amd64/arm64. Eleven
reachable fleet Hosts were rolled out and independently audited at 0.9.6;
Kalibrio/T14 stayed offline. Evidence is under
`/vm-share/software/herden/host-v0.9.6/`. Explicit RGB application rendering
remains a separate unresolved product requirement.
