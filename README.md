<div align="center">

<img src="docs/images/logo.png" width="100" alt="Herden sheep logo" />

# Herden

**The runtime your coding agents live on, with a native iPhone console.**

[Install](#install) · [Pair an iPhone](#pair-an-iphone) · [Host guide](docs/guides/install-host.md) · [Build the iOS app](docs/guides/build-ios.md)

</div>

Herden is a persistent runtime for coding agents. It keeps their terminals,
workspaces and processes alive on a computer you control, even when no client
is attached. The native iPhone app connects to that Herden Host. It does not
connect directly to Claude Code or Codex.

The project is a combined fork of [herdr](https://github.com/herdrdev/herdr)
and [Heeler](https://github.com/ZingerLittleBee/Heeler). It is deliberately
still mostly herdr: the Rust runtime, CLI, workspace model and socket API remain
the foundation of the product. Herden adds Heeler's native iPhone console and
makes secure phone pairing a built-in Host capability.

If you already know herdr, the mental model is simple: run `herden` where you
would run `herdr`, and run `herden pair` when you want to add the iPhone app.

- **Always running:** Agents and their terminals live in the background Host.
  Detach, lose the network or close the client, then reconnect to the same work.
- **Agent aware:** Herden detects supported coding agents and reports whether
  each one is working, blocked, done or idle.
- **Runs your existing tools:** Claude Code, Codex and other supported agents
  run in their normal terminal interfaces. Herden owns the terminal, not the
  agent or its account.
- **Terminal native:** The Host is one Rust binary. Use it from an ordinary
  terminal, locally or over SSH.
- **Available from your phone:** The native iOS app shows Hosts, Spaces and
  Agents, attaches to their real terminal sessions and lets you keep working
  away from the computer.

## Opinionated changes from upstream

Herden stays close to herdr where possible. These are the deliberate product
differences:

- **One Herden product:** the Host runtime and iOS console live in one
  repository and are maintained as one product. Public commands, copy, state
  paths and sockets use the Herden name.
- **Pairing is built in:** `herden pair` creates a short-lived, single-use
  Bootstrap Key and renders the Pairing Code in the terminal. Pairing needs no
  Node installation, plugin action or Herden account.
- **Native iOS console:** the iOS 18+ app is SwiftUI, uses libghostty for the
  terminal and connects with the repository-local SSH implementation. It
  includes direct terminal input, dictation, file staging and Host switching.
- **SSH is the transport:** the app reaches the Host API through OpenSSH
  direct-streamlocal forwarding and attaches to interactive terminals through
  PTY exec channels. There is no central application backend, exposed Host API
  port or `socat` fallback.
- **Private networking is expected:** Tailscale or Headscale is the recommended
  route between phone and Host, although any network path providing ordinary
  OpenSSH can work.
- **Notifications stay optional:** the Node extension and stateless Push Relay
  add encrypted APNs notifications. They are not required for pairing, terminal
  access or normal Host operation.
- **Compatibility beats cosmetic purity:** legacy `HERDR_*` environment names
  and wire identifiers remain where changing them would break compatible
  clients or integrations. They are compatibility surfaces, not product copy.
- **Linux and macOS Hosts first:** these are the supported Herden Host release
  targets today. The iPhone app requires iOS 18 or later.

The Host began from pristine herdr 0.8.2, not the separate customised
`3loc/herdr` fork. The exact source baseline is recorded in
[runtime/UPSTREAM.md](runtime/UPSTREAM.md).

## Upstream policy

Herden treats its two upstream projects differently:

- **Heeler is a historical source, not a maintained upstream.** Herden keeps
  Heeler's native iOS foundation and attribution, but does not plan to merge or
  track later Heeler development.
- **herdr is the active upstream.** Herden intends to keep the Host close to
  herdr so routine upstream changes can be adopted with little or no conflict.
  Herden-specific Host changes should stay small, explicit and covered by tests.

The repository is currently standalone on GitHub and places herdr under
`runtime/`, so GitHub's **Sync fork** button is not available today. Merely
adding a Git remote cannot enable it. Before public launch, using that button
requires Herden to become a real GitHub fork of herdr and to share a compatible
default-branch history and tree layout. Until that migration is complete, do
not describe Herden as automatically synchronised with herdr.

## Install

On a Linux or macOS Host:

```sh
curl -fsSL https://herden.austrheim.ca7.fm/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
herden
```

Herden starts or reattaches to the persistent session in the current working
directory. Install and sign in to Claude Code, Codex or another supported agent
on that Host, then run it inside Herden as usual.

The installer selects the binary for the Host's OS and architecture, verifies
its SHA-256 checksum and installs it to `~/.local/bin`. To compile instead, see
the [Host guide](docs/guides/install-host.md#build-from-source).

## Pair an iPhone

The phone must be able to reach the Host's ordinary OpenSSH service. Tailscale
or Headscale is recommended, and no public router port needs to be opened.

In an ordinary shell on the Host, run:

```sh
herden pair
```

Then open **Herden → Hosts → Add Host** on the iPhone and scan the Pairing Code.
Confirm the Host fingerprint when prompted. The code expires after two minutes
and enrols one phone. Run the command again for another device.

To advertise a particular address or SSH port:

```sh
herden pair --address 100.64.1.2 --port 22
```

See the [Host installation and pairing guide](docs/guides/install-host.md) for
OpenSSH requirements and troubleshooting.

## Install the iPhone app

Herden is a native iOS application. Building it requires a Mac with Xcode 26 or
newer. The Simulator needs no paid Apple membership; a physical-device build
uses an Apple development team and App Group owned by that team.

```sh
git clone https://github.com/3loc/herden.git
cd herden
make sim
```

The [iOS build guide](docs/guides/build-ios.md) covers signing, installing on a
physical iPhone and Wi-Fi deployment.

## Documentation

- [Host installation and pairing](docs/guides/install-host.md)
- [Build and install the iOS app](docs/guides/build-ios.md)
- [Terminal keyboard guide](docs/guides/keyboard.md)
- [Privacy](PRIVACY.md)
- [Architecture decisions](docs/adr/)
- [Optional notification extension](plugin/README.md)

## Development

```sh
make help          # list repository tasks
make host-check    # verify Host build dependencies
make host-install  # build and install the Host
make sim           # build and launch the iOS app in Simulator
make test          # run the iOS and HerdenSSH test suites
```

The Rust Host lives in [runtime/](runtime/). The app, Share Extension and SSH
transport live in [Sources/](Sources/) and
[Packages/HerdenSSH/](Packages/HerdenSSH/). Read
[CONTRIBUTING.md](CONTRIBUTING.md) before contributing.

## Upstream and licence

Herden exists because of both upstream projects. The Host runtime retains
herdr's Apache License 2.0 and attribution in [runtime/LICENSE](runtime/LICENSE).
The iOS application and the combined repository are licensed under the
[GNU Affero General Public License v3](LICENSE).
