---
name: herden-watch-heeler
description: Review new ZingerLittleBee/Heeler changes and selectively port useful iOS fixes into Herden without merging Heeler wholesale. Use when checking Heeler upstream, assessing drift, or reproducing a worthwhile Heeler change.
---

# Watch Heeler upstream

Read [references/lessons.md](references/lessons.md) before starting. Append the
reviewed head and every accepted or rejected product change after each review.

Heeler is provenance and a source of ideas, not a merge upstream. Its exact
history through the Herden fork point and Apache-2.0 relicense is already in
Herden's ancestry. Do not squash, duplicate, or rewrite it.

Configure a fetch-only, no-tags mainline remote when absent:

```sh
git remote add --no-tags -t main heeler-upstream https://github.com/ZingerLittleBee/Heeler.git
git remote set-url --add --push heeler-upstream DISABLED
git fetch --no-tags --prune heeler-upstream main
```

Read the baseline from `UPSTREAM.md`. Verify the fork point and relicense commit
are ancestors of Herden `HEAD`, list commits from the last reviewed Heeler head
to `heeler-upstream/main`, and inspect patches—not only commit subjects.

Classify changes as:

- already present semantically under Herden names;
- useful and worth a small explicit port;
- Heeler-only architecture/product direction;
- CI, release automation, or badges Herden intentionally does not carry.

Never merge Heeler wholesale. Port only a demonstrated improvement into the
current Herden architecture, preserving attribution in the commit message with
the upstream commit hash. Translate public Heeler names to Herden, but retain
legacy herdr wire/compatibility identifiers. Run the smallest relevant suite,
then the full Studio `make test` gate for Swift or project changes.

Update the lessons even when nothing is ported. The next review should start at
the recorded head rather than rediscovering already assessed commits.
