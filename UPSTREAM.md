# Upstream provenance

Herden combines two Apache-2.0 projects with its own product changes.

## Heeler

The native iOS application began from
[`ZingerLittleBee/Heeler`](https://github.com/ZingerLittleBee/Heeler) at commit
[`923a56eb7364b7dd7a8fce3a2f695f3dae4a179a`](https://github.com/ZingerLittleBee/Heeler/commit/923a56eb7364b7dd7a8fce3a2f695f3dae4a179a).

Heeler's contributors explicitly approved relicensing their work from
AGPL-3.0 to Apache-2.0 in
[issue #282](https://github.com/ZingerLittleBee/Heeler/issues/282). The
resulting relicense commit,
[`59792841ccb1005459952a5a981c977e86ddd035`](https://github.com/ZingerLittleBee/Heeler/commit/59792841ccb1005459952a5a981c977e86ddd035),
is the licensing baseline for Herden's iOS sources. The exact Heeler commits
and their ancestry are retained in Herden's public Git history.

Heeler is observed rather than merged wholesale. Later changes are reviewed
and ported only when they remain useful to Herden's current architecture.

## herdr

The Host runtime began from
[`herdrdev/herdr`](https://github.com/herdrdev/herdr). Its exact source commit
and import policy are recorded in [runtime/UPSTREAM.md](runtime/UPSTREAM.md).
Herdr is the active Host upstream; Herden keeps the runtime delta narrow so
upstream changes can be reviewed and adopted without unnecessary conflicts.
Its exact history is retained through subtree merges into `runtime/`.

## License

The combined repository is distributed under the
[Apache License 2.0](LICENSE). [NOTICE](NOTICE) identifies the upstream works
and states that Herden modifies both of them. Existing third-party licence and
attribution files remain alongside the components to which they apply, and the
iOS application exposes redistributed notices under Settings → About →
Acknowledgements.
