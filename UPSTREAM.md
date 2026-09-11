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

## Feature provenance

These origins refer to the imported source baselines, not a comparison with
everything the upstream projects may support today. Integrating or extending
an inherited feature does not make the whole feature a Herden invention.

| Capability | Inherited foundation | Herden's integration or addition |
| --- | --- | --- |
| Persistent Host, terminal sessions and Agent detection | herdr's Rust runtime, CLI and workspace/tab/pane API. | Herden packaging, branding, built-in pairing and a Space-first sidebar. The general runtime model remains available. |
| Native iPhone console and SSH transport | Heeler's SwiftUI app, Ghostty terminal integration and repository-local SSH package. | Space-first navigation and shared Agent/Space terminal controls. |
| QR scanning and secure device pairing | Heeler's camera/paste UI, Apple VisionKit scanner integration, v1 code decoder, Bootstrap Key/Enrollment design and Node pairing plugin. | Host-side pairing moved to Rust `herden pair`; compact v2 encoding and decoding added while retaining v1 support. The scanner itself is inherited. |
| In-app image and file uploads | Heeler's file/image preparation, SFTP staging and Composer upload workflow. | Reused in the shared terminal controls, with direct terminal-path insertion. |
| Sharing from another iOS app | Reuses the inherited preparation, SSH and upload foundations. | Herden's Share Extension target, Agent selection, durable transfer records, recovery and Shared Files history. |
| Notifications, relay and initial website | Heeler's plugin, encrypted notification/Live Activity flow, relay and landing site. | Integrated into the Herden product; pairing removed as a plugin requirement; site and identity subsequently changed. |

### Traceable examples

- The original scanner is in the imported Heeler
  [`PairingScanView.swift`](https://github.com/ZingerLittleBee/Heeler/blob/923a56eb7364b7dd7a8fce3a2f695f3dae4a179a/Sources/Heeler/Pairing/PairingScanView.swift).
  At this audit, Herden's scanner differs only in the displayed Host product
  name. Its camera implementation uses Apple's `DataScannerViewController`.
- The inherited pairing design and Node plugin are documented in
  [ADR 0007](docs/adr/0007-pairing-via-herdr-plugin.md).
  [ADR 0017](docs/adr/0017-unified-herden-host-and-ios-product.md) records moving that
  Host capability into Rust. The import/integration commit is `a6c4a8ad`;
  the compact-code change is `cb2e356b`.
- Heeler already contained `Attachments/AttachmentStaging.swift`,
  `Attachments/ComposerStagingStore.swift` and `Files/FilePreparer.swift`.
  Herden's sharing additions span `a6c4a8ad`, `6c855616` and `01056946`;
  [ADR 0019](docs/adr/0019-share-extension-transfer-recovery.md) explains
  durable transfer recovery.
- [ADR 0022](docs/adr/0022-unified-space-first-console.md) defines Herden's
  Space-first presentation without claiming ownership of herdr's runtime model.

Before changing feature attribution, compare the relevant files against these
baselines and follow their history across renames. Keep this map, README,
NOTICE and website credits aligned; distinguish inherited, adapted and new work.

## License

The combined repository is distributed under the
[Apache License 2.0](LICENSE). [NOTICE](NOTICE) identifies the upstream works
and states that Herden modifies both of them. Existing third-party licence and
attribution files remain alongside the components to which they apply, and the
iOS application exposes redistributed notices under Settings → About →
Acknowledgements.
