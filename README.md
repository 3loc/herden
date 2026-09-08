<div align="center">

<img src="docs/images/logo.png" width="100" alt="Herden sheep logo" />

# Herden

**The runtime your coding agents live on, with a native iPhone console.**

[Website](https://herden.3loc.ltd) · [Download for iPhone](https://testflight.apple.com/join/nSsEZBvv) · [Quick start](#quick-start) · [Host guide](docs/guides/install-host.md) · [Build from source](docs/guides/build-ios.md)

</div>

## Quick start

Do these four things.

### 1. Install Herden on your iPhone

Open the **[Herden public beta on TestFlight](https://testflight.apple.com/join/nSsEZBvv)**.
Install Apple's TestFlight app if asked, then tap **Accept** and **Install**.
If TestFlight says the beta is not accepting testers, Apple's first-build beta
review is still in progress. Try the same link again after it is approved.

### 2. Install the Host on your computer

On your Linux VM, Linux PC or Mac, open Terminal and paste:

```sh
curl -fsSL https://herden.3loc.ltd/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
```

Wait until it says **Herden is ready**.

### 3. Show the QR code

In the same Terminal, paste:

```sh
herden pair
```

Leave the QR code open. It expires after two minutes; run the command again if
that happens.

### 4. Scan it with the iPhone

Open **Herden → Hosts → Add Host**, scan the QR code, then confirm the Host
fingerprint. Open the Host and tap **New Agent** to start Claude Code or Codex.

Your iPhone must be able to reach this computer over SSH. If you want to use
Herden away from home, install Tailscale on both devices and sign in to the
same network first. The [Host guide](docs/guides/install-host.md) has the short
SSH and Tailscale setup if pairing cannot connect.

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
- **Available from your phone:** The native iOS app puts named Agents first,
  attaches to their real terminal sessions and lets you keep working away
  from the computer. Spaces and Hosts provide context.
- **Share straight to an Agent:** Send a screenshot, photo, video or document
  from another app's iOS share sheet to Herden, then pick the Agent. Herden
  uploads the file to its Host, ready for you to add instructions. You can also
  add media and documents directly in the app.
- **Say your next instruction:** Dictate on your iPhone with on-device speech
  recognition. Review the words and send when you're ready.
- **Your machines, one scan away:** Install the Host on a Linux or macOS
  machine on your tailnet, allow SSH from your iPhone, and scan its Pairing Code.
  Add your desktop, laptop or remote VM without opening SSH to the internet.

## Opinionated changes from upstream

Herden stays close to herdr where possible. These are the deliberate product
differences:

- **Agent-first iOS, by choice:** Herden deliberately diverges from its Heeler
  origins. It targets vibecoders who want to work with coding agents
  without needing to be fluent in terminals, tabs and workspace management.
  The default is one Agent to one Space: tap New Agent and Herden creates its
  backing Space automatically, so there is one thing to name, open and return
  to, rather than two separate setup steps. This simplifies the iPhone app,
  not the Host's capabilities. Existing Spaces with several Agents stay intact
  and every Agent remains visible. Explicit Space reuse, linked Worktrees and
  plain terminals remain available through secondary controls. See the
  [Agent-first design decision](docs/adr/0020-agent-first-ios-console.md).
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

- **Heeler is observed, not merged wholesale.** Herden keeps Heeler's native
  iOS foundation and exact history, reviews later Heeler changes, and ports
  useful fixes into the current Herden architecture.
- **herdr is the active upstream.** Herden intends to keep the Host close to
  herdr so routine upstream changes can be adopted with little or no conflict.
  Herden-specific Host changes should stay small, explicit and covered by tests.

The repository is standalone on GitHub and places herdr under `runtime/`, so
GitHub's **Sync fork** button is not available. The exact herdr history is
retained through subtree merges: upstream's repository root maps only to
`runtime/`, while the iOS app and Herden product files stay outside that merge.
See [runtime/UPSTREAM.md](runtime/UPSTREAM.md) and the repo-local upstream skills
under [`.agents/skills`](.agents/skills).

## Host installation details

On a Linux or macOS Host, paste this block into Terminal:

```sh
curl -fsSL https://herden.3loc.ltd/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
```

Herden starts or reattaches to the persistent session in the current working
directory. Run `herden`, then install and sign in to Claude
Code, Codex or another supported agent on that Host and run it inside Herden as
usual.

The installer selects the binary for the Host's OS and architecture, verifies
its SHA-256 checksum, installs it to `~/.local/bin`, and installs its licence
and attribution notice under `~/.local/share/doc/herden`. It configures PATH
for future terminals; the export line makes `herden` available immediately in
the current Terminal. To compile instead,
see the [Host guide](docs/guides/install-host.md#build-from-source).

## Pairing details

The phone must be able to reach the Host's ordinary OpenSSH service. Tailscale
or Headscale is recommended, and no public router port needs to be opened.

In an ordinary shell on the Host, run:

```sh
herden pair
```

If Herden is already open, press **Ctrl-B i** instead. It opens the same
short-lived Pairing Code over the current session in a full-screen popup;
press Ctrl-C to close it.

Then open **Herden → Hosts → Add Host** on the iPhone and scan the Pairing Code.
Confirm the Host fingerprint when prompted. The code expires after two minutes
and enrols one phone. Run the command again for another device.

To advertise a particular address or SSH port:

```sh
herden pair --address 100.64.1.2 --port 22
```

See the [Host installation and pairing guide](docs/guides/install-host.md) for
OpenSSH requirements and troubleshooting.

## Build the iPhone app from source

Most people should install the
**[public TestFlight beta](https://testflight.apple.com/join/nSsEZBvv)**.
Build it yourself only when developing Herden. This requires a Mac with Xcode
26 or newer. The Simulator needs no paid Apple membership; a physical-device
build uses an Apple development team and App Group owned by that team.

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
- [Release the Host](docs/guides/releasing-host.md)
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

Herden exists because of both upstream projects. Heeler's contributors
approved its Apache-2.0 relicense in
[Heeler issue #282](https://github.com/ZingerLittleBee/Heeler/issues/282), and
that relicense is preserved in this repository's history. The Host runtime
retains herdr's attribution in [runtime/LICENSE](runtime/LICENSE). The combined
Herden repository is licensed under the [Apache License 2.0](LICENSE). The
[NOTICE](NOTICE) identifies both upstream works and Herden's modifications.
Exact source commits and maintenance policy are recorded in
[UPSTREAM.md](UPSTREAM.md).
