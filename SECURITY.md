# Security policy

Herden handles SSH identities, Host fingerprints and encrypted notification
keys. Please do not disclose a suspected vulnerability in a public issue.

## Reporting

Use GitHub's
[private vulnerability report](https://github.com/3loc/herden/security/advisories/new).
If private reporting is unavailable before the repository changes visibility,
email `ted@3loc.ltd` with the subject `Herden security report`.
Include the affected Herden version, Host operating system, iOS version and the
smallest reproduction you can provide. Remove private keys, passwords, tokens,
Host addresses and user content before attaching logs.

You should receive an acknowledgement within seven days. A fix and disclosure
timeline will depend on severity and whether coordinated updates are required
for the Host, iOS application or Push Relay.

## Supported versions

Security fixes target the latest published release and the current `main`
branch. Older releases may require upgrading before a fix can be applied.
