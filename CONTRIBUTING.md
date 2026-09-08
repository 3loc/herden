# Contributing to Herden

Issues and PRs are welcome. Bug reports from real setups are especially
valuable. Much of this app is shaped by what breaks in daily use, and a
report that names the herdr version, the SSH topology, and what the screen
showed is already half the fix.

## Orientation

Read these before changing anything non-trivial:

- [`CONTEXT.md`](CONTEXT.md): the domain vocabulary. PRs and issues read
  better when they use these terms the way the codebase does.
- [`docs/adr/`](docs/adr/): the decisions that look strange from the
  outside (the transport design especially) and the dead ends that led to
  them. Challenge them with evidence, not re-litigation.
- [`CLAUDE.md`](CLAUDE.md): the working guide for humans and coding agents
  alike: conventions, load-bearing herdr facts, and the commands that
  matter. Coding agents are first-class contributors here; the repo is
  deliberately structured for them.

The repo carries the Host runtime (`runtime/`), the iOS app (`Sources/`,
`Packages/HerdenSSH`), the optional notification extension (`plugin/`), the
stateless Push Relay (`relay/`), and the marketing site (`landing/`). Pairing is
built into the Host and is not a plugin action.

## Upstream policy

Heeler is historical provenance for the iOS app. Herden does not plan to merge
or track later Heeler changes. herdr is the active Host upstream; keep Herden's
runtime delta narrow and make routine upstream updates easy to review.

The current repository is standalone and nests herdr under `runtime/`. GitHub's
Sync fork button therefore cannot update it. Enabling that workflow requires a
repository migration to a real herdr fork with compatible default-branch
history and layout. Do not confuse a Git remote named `upstream` with GitHub's
fork relationship.

## Building and testing

Everything goes through `make`; run `make help` for the list. The Xcode
project is generated from `project.yml` (XcodeGen; `brew install xcodegen`).
Run `make generate` after changing the YAML. The committed
`Herden.xcodeproj` is part of the source, so commit the regenerated project
alongside the change.

- `make test`: the full app suite plus the `Packages/HerdenSSH` package
  suites (those run through `scripts/run-herdenssh-package-tests.sh`, not
  `-only-testing`).
- One suite:
  `xcodebuild test -project Herden.xcodeproj -scheme Herden -destination
  'platform=iOS Simulator,name=iPhone 17'
  -only-testing:HerdenTests/<SuiteTypeName>`
- `npm test` inside `plugin/` or `relay/` for the Node deliverables
  (Node >= 20, no install step).

A few suites exercise a real SSH server; they skip cleanly on machines
without a local sshd and seeded key. Maintainers can run
`scripts/run-ci-ios-tests.sh` on macOS for the exhaustive disposable-sshd gate.

Two artifact families are generated or shared. Never hand-edit them:

- `Sources/Herden/Transport/Generated/` comes from
  `scripts/generate-wire-types.py --schema scripts/herdr-schema.json`; verify
  it with the generator's `--check` mode.
- `plugin/test-vectors/` is consumed by both the Swift and Node suites, and
  changes in lockstep with `docs/agents/live-activity-contract.md`.

## Conventions

- Swift 6 strict concurrency; no force unwraps or `try!` outside tests.
- Conventional Commits (`feat:`, `fix:`, `docs:`, …) with an imperative,
  lowercase subject.
- User-visible changes get a `CHANGELOG.md` entry under `[Unreleased]`,
  referencing the PR. Internal refactors and test work stay out of it.
- Never hand-edit `MARKETING_VERSION` or create version tags. Releases are
  cut by the maintainer with `make publish`, and `CHANGELOG.md` is the
  source of both the version and the notes.
- Keys and secrets never leave the Keychain and never appear in code, logs,
  or fixtures.

## Reporting security issues

The privacy model (what the relay can and cannot see) is documented in
[PRIVACY.md](PRIVACY.md). Report anything that looks like a vulnerability
through the private process in [SECURITY.md](SECURITY.md), not a public issue.

## License

Herden is licensed under the Apache License 2.0 ([LICENSE](LICENSE));
contributions land under the same license.
