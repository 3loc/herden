---
name: herden-testflight
description: Build, upload, and submit Herden iOS to TestFlight from Studio, replace an outdated beta submission, and manage requested beta invitations. Use for Herden TestFlight work; ordinary device installs use make install.
---

# Herden TestFlight

Read the repository's `docs/guides/releasing.md` and `Makefile` first. They own
the build commands. A successful upload alone does not complete submission.

## Select and preserve the source

- Inspect the current tree, recent device-install notes in `.archive/`, and
  Apple's uploaded builds. Resolve the app using the bundle identifier declared
  in `project.yml`. Never assume Studio's usual checkout is current.
- A device install and an uploaded build can share a version/build number while
  containing different source. Compare source manifests and timestamps; the
  version string alone is insufficient.
- For the latest working changes in a dirty tree, make an isolated snapshot on
  Studio. Include working-tree contents, required untracked source, `Sources/`,
  `Tests/`, `Packages/`, `plugin/test-vectors/`, `scripts/`, the Xcode project,
  `project.yml`, and `Makefile`. Exclude credentials and build caches. Record file
  hashes so concurrent edits cannot silently change what ships.
- Preserve other Studio checkouts' uncommitted work. Compare the snapshot against
  the source of the last working physical-device install when available.

## Build and upload on Studio

1. Select the workflow: `make bump && make testflight` for an interim beta;
   `make publish` only for an explicitly requested versioned release. An interim
   beta does not need a tag or a clean tree. Do not hand-edit marketing versions.
2. Check Apple's existing build numbers before `make bump`; the result must be
   unused. `bump` regenerates the project. If generation fails on missing inputs,
   fix those inputs and run `make generate`, rather than bumping a second time.
3. Run `make test` on the exact snapshot. Report executed/skipped suites accurately;
   local real-SSH fixtures may be absent. Fix relevant failures before uploading.
   Use the locked, fixed-path Studio source and DerivedData lane from the
   release-all skill. Keeping both the project and DerivedData paths stable lets
   Xcode incrementally compile changed sources. Hash the staged source and verify
   the built Info.plists so cache reuse cannot hide stale version metadata. Keep
   `SOURCE_PACKAGES` stable across runs.
4. Authenticate using the environment variables documented in the release guide.
   For this fleet, the available Infisical skill explains authentication and secret
   discovery. Keep secret-store coordinates, credentials and private keys out of
   this public repo. The API helper needs Python 3 and `cryptography`.
5. Set `HERDEN_DEVELOPMENT_TEAM` from the authorised signing-team configuration
   and run `make testflight` with that same fixed-lane `DERIVED`. After an
   earlier Xcode action has resolved the pinned packages successfully, pass
   `XCODE_RESOLUTION_ARGS=-disableAutomaticPackageResolution` so archive does not
   repeat network resolution. Use Studio's logged-in GUI Terminal if SSH signing
   fails with `errSecInternalComponent`; this has succeeded without changing
   accounts, provisioning, or Keychain policy. A script launched via Terminal's
   `do script` should write a log and exit-status file for independent verification.
6. Verify the archived app **and** Share Extension bundle IDs, marketing versions
   and build numbers. Require successful archive/export and check Apple separately.
   Missing dSYMs for pinned CLibSSH2/COpenSSL frameworks have been nonfatal upload
   warnings; record their symbolication limitation without calling the upload failed.

Read [Apple API operations](references/apple-api.md) to finish submission, replace
an older build, or handle invitations. API calls can run from Linux; all Xcode
builds, tests, archives, and uploads stay on Studio and go through `make`.

## Complete and verify

- Wait for Apple's processing to finish, then populate testing notes, associate
  the requested beta groups, and submit for beta review. Use bounded polling with
  progress updates. If processing remains pending, report the exact state and
  preserve the build ID for resumption; do not rebuild or submit blindly.
- A request to submit or invite already authorises that action. A status check
  does not. Use existing authorisation; do not add repeated approval prompts.
  Replacing a specifically outdated build can require expiring it after the new
  build is valid. Do not expire unrelated builds or grant App Store Connect roles
  as an incidental way around external review.
- Re-read the review resource, build state, group membership, and automatic
  notification setting. Distinguish uploaded, processing, waiting for review,
  approved, and invitation sent. Only Apple can approve external testing.
- Copy `make bump`'s `project.yml` and generated project back to the working tree
  only after confirming those files have not changed concurrently. Leave interim
  build edits uncommitted unless the user requested a commit.
- Preserve a source manifest, source archive, signed archive, logs and a concise
  status record under `/vm-share/software/herden/ios-<version>-<build>/`. Verify
  that shared copy, give its exact path, and record durable state in the repo's
  existing `.archive/` convention. Remove temporary credentials and scratch files;
  retain useful release evidence.
