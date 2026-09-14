# Release the Herden Host

Build and validate all four Host assets on macOS through the repository's Make
targets. Publish the runtime distribution at `herden.app` and attach the complete
provenance bundle to a GitHub `host-vX.Y.Z` release. GitHub Actions are not part of
this release path. App releases and interim TestFlight builds follow
[releasing.md](releasing.md).

## Build and validate

Use a clean source snapshot. The build checks the pinned Zig version and writes
a SHA-256 checksum beside each binary. Linux targets use `cargo-zigbuild` on the
Mac. The aggregate target records a source-input receipt, verifies and reuses
completed assets after an interruption, and builds only missing or corrupt ones.

For Host 0.9.0:

```sh
make host-release HOST_VERSION=0.9.0 OUT_DIR=release/host-v0.9.0
make host-test
make host-perf HOST_BASELINE=/path/to/previous-public-herden \
  HOST_CANDIDATE="$PWD/release/host-v0.9.0/herden-macos-aarch64"
```

Resume with the same command and directory. A mismatched source receipt is a
hard failure: use a new empty directory rather than mixing assets from two
source states.

Keep the performance baseline binary from the previous public release. Run the Linux
pairing/upgrade PTY checks with both the candidate and previous public binary,
then compare the candidate's exported API schema with the committed snapshot.

When running the resumable build through nested SSH/tmux/caffeinate shells, set
`ZIG` in the innermost command environment (for example,
`env ZIG=/path/to/zig-aarch64-macos-0.16.0/zig
sh scripts/build-host-release.sh ...`). An outer export can be lost while the
Make recipe rebuilds `PATH`, causing the asset script to fall back to a
different `zig` or report the pinned version as missing.

Inspect the fixed lane's ignored `.herden.local.mk` before invoking a Make
target. It survives source syncs by design, so a lane previously staged from
Linux can retain `/home/...` cache and Zig paths; Make assignments there can
override an otherwise-correct shell `CARGO_TARGET_DIR`. Correct the lane-local
file for Studio or invoke the underlying release/test script with every tool
and cache path set in its innermost environment.

Do not overlap cross builds or native tests sharing one source directory:
`runtime/vendor/libghostty-vt/zig-out/lib` is shared even when Cargo target
directories differ. After a cross build, invalidate the vendor build (touch its
`VERSION` file without changing its contents) before running native tests.
Timed shell tests need a clean temporary `HOME`; preserve the real `CARGO_HOME`
and `RUSTUP_HOME` so shell plugins and user startup commands cannot skew them.
The performance harness isolates scenario homes itself.

On Studio, Zig 0.15.2 required the Command Line Tools macOS 15.4 SDK for the
Intel Darwin cross build; the Xcode 26 SDK's stubs failed target selection.
Select the compatible SDK in the task's tool environment, without changing the
machine-wide Xcode selection.

## Publish before fleet rollout

1. Verify all four binaries and checksums. Update root `install.sh` and its
   identical `landing/public/install.sh` copy to the exact new Host version.
2. Commit and push the release inputs. Preserve a source archive and build-input
   hashes, including the exact commit provenance, in durable operator storage
   and the GitHub release.
3. While the repository is private, publish only the four binaries and their
   checksums, `install.sh`, `latest.json`, `LICENSE`, `NOTICE`, `SHA256SUMS`, and
   an optional release README under `https://herden.app/releases/host-v0.9.0/`.
   Do not publish source archives, source manifests, or build-input receipts.
   Recheck repository visibility on every release; this boundary changes only
   when the repository is deliberately made public again. Publish the matching root
   `install.sh` and `latest.json`, deploy the current landing build, and invalidate
   their CDN paths. Production infrastructure remains outside this repository.
4. Create the GitHub `host-v0.9.0` release at the source commit and attach the
   complete bundle, including the private source/provenance files. Verify public
   download digests and private GitHub asset digests against local hashes.
5. Test the **public URL** in disposable Linux amd64 and arm64 containers: fresh
   installation, idempotent repeat, and upgrade from the previous public release.
   Check version, published checksum, pairing and shell command lookup. Run the
   installer's Docker PATH suite too.
6. From the `3loc` fleet controller, run `make herden LIMIT=3loc,studio`, then
   `make herden`, followed by the independent `make herden-check` audit. The fleet
   must use the public installer; `SOURCE`, `REF`, and snapshots are retired.

The installer leaves existing servers running their current executable. The
fleet rollout uses live handoff to upgrade stale Herden sessions while preserving
panes, and the independent audit verifies their versions as well as the installed
binary. Older attached clients still need reopening. Report unreachable Hosts as
pending; a successful reachable rollout does not mean offline laptops upgraded.

Save release assets, signed iOS archives when applicable, source provenance and
validation evidence in durable operator storage.
