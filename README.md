<div align="center">

<img src="docs/images/logo.png" width="96" alt="Herden sheep logo" />

# Herden

**Keep your coding agents running. Take them with you.**

[Get started](docs/guides/install-host.md) · [Build the iPhone app](docs/guides/build-ios.md) · [Keyboard guide](docs/guides/keyboard.md)

</div>

Herden connects your iPhone to Claude Code and Codex running on a computer you
control. See what they are doing, answer a question, dictate a prompt, or share
a document from another app. Your work stays on that computer.

Herden is one project with two parts:

- **Host:** the program that keeps terminal sessions running on Linux or macOS.
  Its command is `herden`. It includes the runtime derived from herdr and built-in
  QR pairing. You do not need a separate herdr installation or a plugin.
- **iPhone app:** the native interface to your Hosts, Spaces and Agents.
  Spaces group your work; Agents are the Claude or Codex processes doing it.

## Start here

You need a Linux or macOS Host, an iPhone with iOS 18 or later, and a Mac with
Xcode if you are building the app yourself. Install and sign in to Claude Code
or Codex on the Host first, using your own account.

**Release status:** this checkout contains the unified Host and iOS source.
Public Host binaries have not been published yet. Use the source installation
below today; the release installer is ready for the first binary release.

### 1. Install the Host

Follow the [Host installation guide](docs/guides/install-host.md) to install the
build tools. Then, in the Host's Terminal:

~~~sh
git clone https://github.com/3loc/herden.git
cd herden
make host-install
export PATH="$HOME/.local/bin:$PATH"
herden
~~~

Herden opens a persistent terminal session. Leave the Host powered on and awake.
Disconnecting the phone does not stop your Agents; shutting down the Host does
stop running processes.

After binary releases are available, installation will be:

~~~sh
curl -fsSL https://raw.githubusercontent.com/3loc/herden/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
herden
~~~

The installer verifies the download's SHA-256 checksum and installs to
`~/.local/bin`. The core product needs no Node, npm, plugin or push relay.

### 2. Connect your Host and phone with Tailscale

Install [Tailscale](https://tailscale.com/download) on both devices, sign in to
the same network, and connect. Keep ordinary OpenSSH enabled on the Host:
Herden uses its SSH Device Key and Unix-socket forwarding over the Tailscale
connection. Leave the separate **Tailscale SSH** feature disabled on this Host.
See [SSH over Tailscale](https://tailscale.com/docs/reference/ssh-over-tailscale)
and [our setup steps](docs/guides/install-host.md#connect-with-tailscale).

Headscale users can join their existing private network instead. Herden does
not require access to 3LOC's network or domains. You do not need to forward a
port on your home router.

### 3. Install the iPhone app

The [iOS build guide](docs/guides/build-ios.md) covers installing Xcode, signing
with your own Apple team, Developer Mode, and deploying by USB or Wi-Fi.
The Simulator is also available for trying the interface.

### 4. Show the QR code and scan it

In an **ordinary shell tab inside your Herden session**, run:

~~~sh
herden pair
~~~

Do not type this into Claude or Codex's message field. A second Terminal window
under the same Host user works too.

On your iPhone, open **Herden → Hosts → Add Host**, choose the scanner, and point
the camera at the QR code. Check the Host fingerprint when asked. Once paired,
choose or create a Space, then open an Agent. The code expires after two minutes;
run the command again if needed. Repeat for each phone.

To advertise a specific Tailscale address:

~~~sh
herden pair --address 100.64.1.2
~~~

Replace the example with your Host's address from Tailscale. Pairing is built
into Herden. The iPhone generates its permanent private key locally and keeps
it in the Keychain.

## How it feels

Tap a Space or Agent to open its terminal. Swipe right across terminal output
to return to the picker; swipe left in the picker to reopen the last session.
The bottom Agent strip lets you switch directly between Agents.

The keyboard serves the terminal. Type or dictate into the actual prompt,
touch it to place the cursor, then drag left or right to adjust it. Dragging
within the prompt is editing; swiping across output is navigation. The control
deck holds Esc, Ctrl-C, vi controls, dictation, Return and one keyboard toggle.

Herden launches and restores Claude and Codex with their native vi editing
enabled. **Press i to type; press Esc to return to movement commands.** Existing
processes keep their current mode. See the [keyboard guide](docs/guides/keyboard.md)
for manually launched agents and editing examples.

Dictation offers Traditional Chinese (Taiwan), Simplified Chinese, Swedish,
Portuguese (Portugal), and English (US), where the iPhone has an on-device
recogniser. Dictation never presses Return. Touching the prompt stops dictation
before you move the cursor, so a later speech correction cannot overwrite your edit.

## Privacy and optional services

Terminal traffic and shared files travel directly between your iPhone and Host
over SSH. Herden has no account service in that path. Your Claude or Codex
provider still processes what you send to that Agent under its own terms.

The notification extension and Push Relay are optional. The 3LOC relay is
private infrastructure, not a public service included with your installation.
Core pairing and remote control work without it. See
[plugin/README.md](plugin/README.md) and [PRIVACY.md](PRIVACY.md).

## Develop and contribute

~~~sh
make help          # available tasks
make host-check    # check Host build tools
make host-install  # build and install the Host
make sim           # run the app in a Simulator, on a Mac
make test          # run iOS and SSH package tests, on a Mac
~~~

The Rust Host lives in [runtime/](runtime/). The app, Share Extension and SSH
transport live in [Sources/](Sources/) and [Packages/HerdenSSH/](Packages/HerdenSSH/).
See [CONTRIBUTING.md](CONTRIBUTING.md) and the [architecture decisions](docs/adr/).

The iOS app began as [Heeler](https://github.com/ZingerLittleBee/Heeler) and
retains that history. The Host began from pristine
[herdr](https://github.com/herdrdev/herdr), with provenance in
[runtime/UPSTREAM.md](runtime/UPSTREAM.md). The app uses [AGPL v3](LICENSE);
the upstream-derived runtime retains [Apache 2.0](runtime/LICENSE).
