# Heeler review lessons

## 2026-09-08 — reviewed through `3ac42a7`

- Herden contains the exact Heeler fork point
  `923a56eb7364b7dd7a8fce3a2f695f3dae4a179a` and Apache-2.0 relicense
  `59792841ccb1005459952a5a981c977e86ddd035` as real ancestors.
- Ten upstream commits followed the recorded fork point. Most are merge commits
  or CI path-filter/concurrency work that Herden intentionally does not carry.
- The only new product fix was `58b5696`: run the remote home-directory probe
  under `/bin/sh` so nushell cannot leave `$HOME` unexpanded. Herden already
  contains the same behavior and dedicated `HomeCommandTests`, translated to
  `__HERDEN_HOME__`; no port was necessary.
- Heeler's later license commit is already merged into Herden ancestry and its
  attribution is present in `UPSTREAM.md` and `NOTICE`.
