---
name: herden-release-all
description: Release the latest Herden product everywhere by composing the Host/public/fleet release, Tedda install, Vivian install, and TestFlight workflows from one verified source state. Use when Ted asks to update, deploy, or release all of Herden.
---

# Release all of Herden

This is the master Herden deployment skill. Before acting, read and follow all
four component skills completely:

- `../herden-release-host/SKILL.md`
- `../herden-install-tedda/SKILL.md`
- `../herden-install-vivian/SKILL.md`
- `../herden-testflight/SKILL.md` and its Apple API reference when submission or
  review state is involved

Also read both release guides, `Makefile`, and the newest relevant `.archive/`
entries. The user's request to run this skill authorises the described device,
Apple beta, public Host, GitHub, website, and fleet mutations. It does not
authorise deleting unrelated apps, credentials, releases, data, or dirty work.

## One source ledger

Record the starting commit, tracked diff, required untracked files, source
manifest, app version/build, Host version, public versions, Apple build state,
and both device states. Re-hash before every irreversible publication boundary.
If the source changes concurrently, stop rather than mixing builds.

Use a single isolated, hashed Studio snapshot for iOS tests, both physical-device
installs, archive, and upload. Choose exactly one run-specific `DERIVED` directory
and one run-specific `SSH_DERIVED` directory and pass those same two paths through
the tests, both device installs, archive, and upload; changing them between stages
needlessly rebuilds the Swift package graph. A build already on a device or TestFlight counts as
current only when its preserved source manifest matches—not merely its version
number. Conversely, if Apple's valid, approved build already matches the exact
source, verify it and do not create a needless new build.

The Host release uses a clean immutable release commit and its own four-platform
artifacts. Never overwrite a published Host version. Commit and push requested
skill/release inputs before tagging, while preserving any unrelated local edits.

## Fast redeploy path

Classify the changed paths before doing expensive work. A request to redeploy
everything means make every surface current; it does not mean rebuild immutable
artifacts whose source manifest is already deployed.

- iOS-only changes run the iOS tests, both device installs, and TestFlight flow.
- landing-only changes build and deploy the site, preserving Host release files.
- Host/runtime/installer changes run the full Host release and fleet flow.
- skill or documentation-only changes need no product rebuild.

Sync the working source directly to one new Studio directory with `rsync`,
excluding `.git`, `node_modules`, `.build`, `DerivedData`, and other generated
outputs. Do not make an intermediate `/tmp` copy. Hash only release inputs, and
reuse successful test/build receipts keyed by that exact manifest. Use existing
dependency caches and run independent read-only preflights concurrently. Run long
Studio builds inside a named reconnectable session under `caffeinate -dimsu`, with
output written to the release evidence directory. Run stdin-sensitive test suites
as detached non-TTY `nohup caffeinate ... </dev/null` jobs instead of putting them
inside tmux. An SSH disconnect must not kill or obscure healthy work. Report
the active gate promptly; if a command fails, diagnose that gate without
restarting already-proven unchanged surfaces.

## Execution order and gates

1. Classify changed surfaces, then preflight Studio, both devices, Apple credentials/state, GitHub, AWS/CDN,
   Docker or real architecture runners, the fleet controller, signing identity,
   disk space, and source stability.
2. Create and verify the shared iOS snapshot. Run the complete iOS and HerdenSSH
   test surfaces once.
3. Install and independently verify the same app on Tedda and Vivian.
4. Upload only if the exact source is absent from TestFlight. Wait for processing,
   update notes/groups, enable automatic notification, submit for beta review,
   and replace only the specifically superseded build when necessary. Re-read
   Apple state before reporting distribution.
5. If Host release inputs changed, cut and validate the next immutable Host release, then publish the four
   binaries, checksums, installer, manifest, landing site, and GitHub release.
6. Pass public fresh/repeat/upgrade tests on both architectures before canarying
   and rolling the public installer through the reachable fleet. Finish with the
   independent fleet audit.
7. Re-verify the live site and logo, every advertised Host asset, installer and
   update manifest, GitHub release, Apple state, and both device installations.

If a later gate fails, preserve earlier valid outcomes and evidence; do not undo
a working device install or expire a working Apple build merely to make the run
look atomic. Do not call the master run complete while any advertised public
artifact disagrees. Report offline devices/hosts and external Apple review as
explicit pending states.

Store one master ledger plus component logs, manifests, archives, binaries,
checksums, and audits under a timestamped
`/vm-share/software/herden/release-all-YYYYMMDD-HHMMSS/` directory. Update
`.archive/` and `.archive/MEMORY.md`, and report exact versions, commits, device
states, TestFlight state, public hashes, fleet status, and the shared path.
