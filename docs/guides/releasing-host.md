# Release the Herden Host

Build and validate all four Host assets on macOS through the repository's Make
targets. Publish the complete versioned bundle at `herden.3loc.ltd` and attach
identical assets to a GitHub `host-vX.Y.Z` release. GitHub Actions are not part of
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
   hashes, including the commit used for the published `source.json` provenance.
3. Publish the complete assembled directory under
   `https://herden.3loc.ltd/releases/host-v0.9.0/`. Publish the matching root
   `install.sh` and `latest.json`, deploy the current landing build, and invalidate
   their CDN paths. Production infrastructure remains outside this repository.
4. Create the GitHub `host-v0.9.0` release at the source commit and attach the same
   bundle. Verify public downloads and GitHub asset digests against local hashes.
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
validation evidence under `/vm-share/software/herden/` for the operator.
