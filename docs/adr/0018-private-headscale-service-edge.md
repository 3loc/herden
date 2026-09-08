---
status: accepted
---

# Keep infrastructure deployment outside the product repository

The public site is `herden.3loc.ltd`. The maintainer-operated Push Relay has a
separate endpoint because it handles APNs credentials and must be deployable
independently from static web content.

This repository owns application code and build verification only. DNS, TLS,
network policy, secrets, workload definitions and live deployment verification
belong to the operator's infrastructure repository. No infrastructure hostnames,
network topology, secret-store coordinates or credentials belong in Herden's
public history.
