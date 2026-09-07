---
status: accepted
---

# Keep Herden's web services behind the 3loc Headscale tailnet

The Herden site is `herden.austrheim.ca7.fm` and the Push Relay is
`herden-apns.austrheim.ca7.fm`. Both run inside the Austrheim homelab and are
served by the native Traefik edge on nidavellir. Split-horizon DNS resolves the
names to that edge for LAN and Headscale clients.

Headscale, self-hosted on Hetzner for the `3loc.ltd` tailnet, is the remote
access layer. The services have no public WAN ingress and do not use a public
Cloudflare Worker or tunnel. The existing wildcard certificate is issued by
DNS-01, so TLS does not require an inbound HTTP challenge.

The Herden repository owns application code and build verification. The fleet
repository is the declarative source of truth for workloads, Traefik routers,
split-DNS aliases, Headscale policy, secrets, deployment, and live verification.
