---
name: herden-install-tedda
description: Build, install, launch, and verify the latest Herden iOS source on Ted's iPhone Tedda through Studio. Use only for direct Tedda device deployments; TestFlight distribution uses herden-testflight.
---

# Install Herden on Tedda

Read `Makefile`, the newest Tedda entry in `.archive/`, and
`.agents/skills/herden-testflight/SKILL.md` for source-snapshot rules.

Tedda's CoreDevice identifier is
`28309636-A280-52AE-8936-EE3440A1D74B`. Resolve it by both name and identifier on
Studio before installing; its hardware UDID must be resolved live from
`devicectl`, not hardcoded. Stop if they disagree or the device is unavailable.

- Capture the requested working tree as a hashed, isolated Studio snapshot.
  Preserve Studio's other checkouts and their uncommitted work. Reuse the
  master's snapshot when invoked by `herden-release-all`.
- Confirm `project.yml` and the generated Xcode project agree. Use the canonical
  bundle ID `ltd.3loc.herden`; do not reinstall or revive the retired
  `com.3loc.herden` identity.
- Run the relevant iOS test gate once per source snapshot, then run
  `make install DEVICE=28309636-A280-52AE-8936-EE3440A1D74B` on macOS. When the
  release-all workflow already built the exact app and its embedded profiles
  contain Tedda's live hardware UDID, use `make install-built` instead; this must
  not invoke Xcode again. Reuse the master workflow's locked, fixed-path Studio
  source and DerivedData lane. For a standalone install, use that same lane rather
  than a new timestamped checkout, and verify the built Info.plist before install;
  invalidate only its scoped products if metadata is stale. Set
  `IOS_BUILD_DESTINATION=id=<hardware-UDID>` so automatic signing
  selects a profile valid for Tedda. Pass the authorised development team without
  committing it.
- If SSH codesigning fails with `errSecInternalComponent`, run the exact command
  in Studio's logged-in GUI Terminal. Do not alter Keychain or signing policy.
- Independently query CoreDevice after `make` returns. Require the installed app
  bundle ID, marketing version, build number, installation URL, and a running
  process for `ltd.3loc.herden` to match the built app. Query the built app's
  Info.plist as well; a successful compile is not an install verification.

Preserve the snapshot manifest and install log with the master-run evidence under
`/vm-share/software/herden/`. Record the deployment in `.archive/` without
claiming Vivian or TestFlight was updated.
