---
name: herden-install-vivian
description: Build, install, launch, and verify the latest Herden iOS source on Vivian's iPhone through Studio. Use only for direct Vivian device deployments; TestFlight distribution uses herden-testflight.
---

# Install Herden on Vivian

Read `Makefile`, the newest Vivian device entry in `.archive/`, and
`.agents/skills/herden-testflight/SKILL.md` for source-snapshot rules.

Vivian's iPhone 15 CoreDevice identifier is
`4A64C00D-A665-5B87-A1E9-F60AA029DE9E`. Resolve it by both name and identifier on
Studio before installing; resolve its hardware UDID live from `devicectl` and
confirm that device is enabled on the authorised Apple developer team. Register
it through Apple's device API if the requested deployment requires that normal
provisioning step. Stop if identities disagree or the device is unavailable.

- Capture the requested working tree as a hashed, isolated Studio snapshot.
  Preserve Studio's other checkouts and their uncommitted work. Reuse the
  master's snapshot when invoked by `herden-release-all`.
- Confirm `project.yml` and the generated Xcode project agree and build the
  canonical `ltd.3loc.herden` app. Do not delete an older app identity or its
  data unless the user explicitly requests migration cleanup.
- Run the relevant iOS test gate once per source snapshot, then run
  `make install DEVICE=4A64C00D-A665-5B87-A1E9-F60AA029DE9E` on macOS. When the
  release-all workflow already built the exact app and its embedded profiles
  contain Vivian's live hardware UDID, use `make install-built` instead; this must
  not invoke Xcode again. Reuse the master workflow's locked, fixed-path Studio
  source and DerivedData lane. For a standalone install, use that same lane rather
  than a new timestamped checkout, and verify the built Info.plist before install;
  invalidate only its scoped products if metadata is stale. Set
  `IOS_BUILD_DESTINATION=id=<hardware-UDID>` so Xcode refreshes or
  creates a profile valid for Vivian. Pass the authorised development team
  without committing it.
- If SSH codesigning fails with `errSecInternalComponent`, run the exact command
  in Studio's logged-in GUI Terminal. Do not alter Keychain or signing policy.
- Studio intentionally may not have an interactive account for the authorised
  team. In that case, use the Apple API to create app and Share Extension
  development profiles containing the current development certificate plus
  both enabled phones. Install each profile under its embedded UUID in
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`, then build with
  `IOS_SIGNING_ARGS=CODE_SIGN_STYLE=Manual`,
  `HERDEN_APP_PROVISIONING_PROFILE_UUID`, and
  `HERDEN_SHARE_PROVISIONING_PROFILE_UUID`. Do not retry automatic signing after
  this condition is known, and do not replace or delete unrelated profiles.
- Independently query CoreDevice after `make` returns. Require the installed app
  bundle ID, marketing version, build number, installation URL, and a running
  process for `ltd.3loc.herden` to match the built app. Query the built app's
  Info.plist as well.

Preserve the snapshot manifest and install log with the master-run evidence under
`/vm-share/software/herden/`. Record the deployment in `.archive/` without
claiming Tedda or TestFlight was updated.
