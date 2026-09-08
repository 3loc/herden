---
name: herden-sync-herdr
description: Synchronize Herden's runtime subtree with herdr upstream while preserving exact upstream ancestry, Herden branding, pairing, compatibility surfaces, and release safety. Use for checking, planning, or performing a herdr update in the Herden repository.
---

# Sync Herden with herdr

Read [references/lessons.md](references/lessons.md) before starting. Update it
after every completed or aborted sync with facts that would change the next
attempt.

## Invariants

- Upstream repository: `https://github.com/herdrdev/herdr.git`, main branch
  `master`.
- Herdr's repository root maps only to Herden's `runtime/` directory.
- The initial exact baseline `702aa1e45527509bec73dad9b8d443f449c0379b`
  and subsequent upstream heads must remain real ancestors of Herden, not
  squashed snapshots.
- Never fetch upstream tags into Herden's tag namespace. Herdr and Herden both
  use `v0.x` names. Configure the remote with `--no-tags` and only its mainline.
- Never push to upstream. Give the upstream remote a disabled push URL.
- Keep `HERDR_*`, wire names, schema provenance names, and other compatibility
  identifiers unless a migration is explicitly designed. Public commands,
  executable/package identity, state paths, URLs, and product copy stay Herden.
- Keep `runtime/docs/` byte-for-byte upstream. It contains herdr's archived
  documentation; Herden's public documentation lives at the repository root
  and in `landing/`.
- A source sync does not authorize publishing binaries or rolling them out.

## Audit

Require a clean `main` worktree and fetch without tags:

```sh
git remote add --no-tags -t master herdr-upstream https://github.com/herdrdev/herdr.git
git remote set-url --add --push herdr-upstream DISABLED
git fetch --no-tags --prune herdr-upstream master
```

If the remote exists, verify its fetch URL, `remote.herdr-upstream.tagOpt` is
`--no-tags`, its only fetch refspec is `master`, and its push URL is disabled.
Read the initial and last-synchronized commits from `runtime/UPSTREAM.md`, then
verify both are ancestors of `HEAD`. Report upstream commits and release notes
since the last synchronized commit before changing files.

## Merge

Work on a temporary branch/worktree. For ordinary updates:

```sh
git merge -s subtree --no-commit herdr-upstream/master
```

The one-time ancestry anchor already exists; do not recreate it. Resolve only
real Herden deltas. Expected long-lived conflicts are the `herden` package
name/version, the short custom `runtime/README.md`, branded machine-setup
fixtures, and files upstream deletes after Herden has branded them. Prefer an
upstream deletion unless Herden still has a demonstrated caller.

After resolving, compare `runtime/docs/` with the upstream tree and restore
the upstream copy if Git retained an old mechanical branding edit.

Audit newly added user-facing `herdr` strings. Do not mass-replace internal or
compatibility names. Ensure update endpoints still use `herden.3loc.ltd` and no
upstream release asset can replace the Herden executable.

Update `runtime/UPSTREAM.md` with the exact merged commit. Build the merged
Host, export its schema, replace `scripts/herdr-schema.json`, and run
`scripts/generate-wire-types.py --schema scripts/herdr-schema.json`. Never
hand-edit generated wire types.

## Validate and finish

Run formatting, the full locked Host suite, and
`scripts/test-pairing-input.py`. A single failure must be rerun alone to
distinguish a parallel-test race from a deterministic regression. If separate
parallel runs fail different tests that both pass alone, use a complete
single-threaded run as the deterministic acceptance gate and record the new
race. Schema changes require the full Studio `make test` gate from an isolated
snapshot.

Commit the subtree merge with the exact upstream short hash in its subject and
confirm the merge commit's second parent is that exact upstream commit. Remove
the temporary worktree/branch after integration, leave `main` clean, and append
new conflict resolutions, regressions, and validation traps to the lessons.
