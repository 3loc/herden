---
name: herden-release-host
description: Release the latest Herden Host source across the four supported Linux/macOS targets, public website and installer, GitHub release, and 3LOC fleet. Use for publishing or completing a Herden Host release; ordinary local source builds do not use this skill.
---

# Release the Herden Host

Read `docs/guides/releasing-host.md`, `Makefile`, and the newest Host-release
entry in `.archive/` before acting. A Host release is one public-to-fleet
operation; do not call it complete after uploading only some artifacts.

## Choose the smallest safe operation

Compare current paths and deployed manifests first. If only `landing/` changed,
run a site-only build/deploy and CDN invalidation while preserving `install.sh`,
`latest.json`, and `releases/`; do not rebuild, retag, or roll out the unchanged
Host. If the public Host release already matches the current Host inputs, verify
its assets and fleet state instead of manufacturing another version. The full
four-platform workflow below is required only when runtime, installer, release
metadata, or Host-facing compatibility inputs changed.

## Establish the immutable release source

- Inspect the worktree, `origin/main`, the newest `host-v*` tag, runtime version,
  root and landing installer copies, live `latest.json`, and GitHub releases.
- Never overwrite an existing versioned release. If current Host source is newer
  than the newest tag, choose the next patch version unless the user supplied a
  version, update `runtime/Cargo.toml` and `Cargo.lock`, both installer copies,
  and the release-note metadata template, then commit and push those release
  inputs before building.
- Keep unrelated dirty work intact. Build from a clean, hashed source snapshot on
  Studio; all four distributable assets must come from the same commit.
- Confirm `runtime/src/update.rs` stable and preview URLs remain on
  `herden.3loc.ltd`. Never publish an executable or update manifest that can
  replace Herden with an upstream herdr asset.

## Build and validate on Studio

Build serially through the Make targets for:

- `x86_64-unknown-linux-musl`
- `aarch64-unknown-linux-musl`
- `x86_64-apple-darwin`
- `aarch64-apple-darwin`

Use one explicit release directory and run `make host-release-assemble` only
after all binaries and checksum files exist. Do not overlap cross-builds or
native tests because libghostty-vt shares `zig-out`. Follow the SDK and cache
constraints in the release guide.

Keep the pinned Zig 0.15.2 and cargo-zigbuild 0.23.4 under
`~/.cache/herden-release-tools/` on Studio and put them first on `PATH`; install
them once when absent, not on every release. The Make targets automatically
route Zig's macOS SDK lookup through the CLT 15.4 SDK when it exists, avoiding
the Xcode 26 linker failure without changing machine-wide developer tools.

Run the full locked Host suite, pairing/upgrade PTY checks, exported-schema
comparison, installer suite, and the performance gate against the previous
public binary. Record exact pass/fail counts and hashes.

For the full Host suite, set `HOME` to a fresh task-local directory while
preserving the real `CARGO_HOME`, `RUSTUP_HOME`, and shared `CARGO_TARGET_DIR`.
User shell/config state can otherwise make command-spawning tests fail even
though the runtime is correct. If a first run omitted this isolation, rerun the
affected tests under the clean home before diagnosing product code.

## Publish as one coherent bundle

1. Upload the complete versioned directory to
   `s3://herden-3loc-ltd/releases/host-vX.Y.Z/` without deleting older releases.
2. Publish the matching root `install.sh` and `latest.json`, then deploy the
   current `landing/dist` without deleting either root Host file or `releases/`.
3. Invalidate the changed CloudFront paths and wait for completion.
4. Create annotated `host-vX.Y.Z` at the exact release commit, push it, and create
   the GitHub Host release with the same assembled files. Never reuse or move a
   published tag.
5. Compare every public and GitHub asset byte-for-byte with the local release,
   and verify content types plus the live landing page/logo.
6. Test the public installer in disposable amd64 and arm64 Linux environments:
   fresh install, repeat, and upgrade from the previous public version. Verify
   installed version and SHA-256 against live metadata. If local emulation cannot
   execute one architecture, use a real matching fleet host; a digest-only check
   is not the complete release gate.
7. From the `3loc` fleet controller run the public-installer rollout, canarying
   `3loc,studio` first, then all reachable `herden_hosts`, followed by the
   independent `make herden-check` audit. Source/snapshot rollout modes are not
   allowed. Report offline hosts as pending.

Copy the exact release bundle, source provenance, logs, public verification, and
fleet audit to `/vm-share/software/herden/host-vX.Y.Z/`. Update `.archive/` and
its index. Report the tag, source commit, all four hashes, public version, fleet
status, and the shared evidence path.
