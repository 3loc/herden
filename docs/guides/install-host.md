# Install and pair a Herden Host

A Host is the computer that runs your coding agents. Run these commands on
that computer, as the user who will run Claude or Codex. Paste one block at a
time into Terminal and press Return. A `sudo` password prompt asks for that
computer's password; it does not show characters while you type.

## Enable SSH

On Ubuntu or Debian:

```sh
sudo apt update
sudo apt install openssh-server
sudo systemctl enable --now ssh
```

On macOS, open **System Settings → General → Sharing → Remote Login**. Enable
it and allow your user account. Keep the Host awake for remote access.

Herden needs public-key authentication, PTY sessions and OpenSSH stream-local
forwarding. Standard OpenSSH defaults allow them. On a hardened Host, ask its
administrator to permit `AllowStreamLocalForwarding yes` and check that
`DisableForwarding` is not enabled for your user. Herden does not alter SSH or
firewall configuration.

## Connect with Tailscale

1. Install [Tailscale on the Host](https://tailscale.com/download). On Linux,
   the [official guide](https://tailscale.com/docs/install/linux) provides
   distribution packages and this convenience installer:

   ```sh
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   tailscale ip -4
   ```

   Open the sign-in link. Save the `100.x.x.x` address printed by the last
   command. On macOS, sign in through the Tailscale app.
2. Install Tailscale on the iPhone, sign in to the same network, allow its VPN
   configuration, and connect. Both devices should appear in the device list.
3. Keep **ordinary OpenSSH** as the SSH server. Do not enable `tailscale up --ssh`:
   [Tailscale SSH takes over port 22 on the Tailscale address](https://tailscale.com/docs/features/tailscale-ssh).
   If already enabled on Linux, `sudo tailscale set --ssh=false` returns that
   address to OpenSSH. Herden pairs its own SSH key and needs Unix-socket forwarding.

The network policy and Host firewall must allow the phone to reach the Host
on TCP port 22. No router port forwarding is needed. Headscale users follow
their administrator's enrolment instructions to join their existing network.
Herden does not require 3LOC's private network.

## Install the Host

Install the release binary on Linux or macOS:

```sh
curl -fsSL https://herden.3loc.ltd/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
```

The installer selects the binary for the Host's OS and architecture, verifies
its SHA-256 checksum, installs it to `~/.local/bin`, and installs the release's
licence and attribution notice under `~/.local/share/doc/herden`. It adds the
install directory to your shell startup files when needed: the active login
profile and `~/.bashrc` for bash, `~/.zprofile` and `~/.zshrc` for zsh (respecting
`ZDOTDIR`), or `~/.profile` for POSIX shells. Reinstalling does not duplicate
these entries. Other shells need their own PATH configuration.

The export line makes `herden` available in the current Terminal immediately;
a piped installer cannot change its parent shell's environment. Run
`herden --version` or `herden pair` in that same Terminal.

The same command upgrades an existing installation. It is idempotent: when the
installed binary already matches the current release, it is verified and left
in place. An already-running Herden session keeps its existing process until it
is restarted.

## Build from source

Use this route to develop the Host or build a revision that has not been
released. Compilation can take several minutes.

On Ubuntu or Debian, install the build tools:

```sh
sudo apt install build-essential cmake pkg-config git curl
```

On macOS, install Xcode's command-line tools with `xcode-select --install`.
Install [Rust with rustup](https://rustup.rs/) and a current stable toolchain;
the release workflow uses Rust 1.96.1.

Install **Zig 0.15.2**, the exact version required by the bundled terminal
engine, from [Zig downloads](https://ziglang.org/download/). Extract the archive
for your OS and CPU, and add its directory to PATH. Alternatively, set `ZIG`
to the full path of its `zig` executable. A newer Zig is not interchangeable.

```sh
rustc --version
cargo --version
zig version
git clone https://github.com/3loc/herden.git
cd herden
make host-check
make host-install
export PATH="$HOME/.local/bin:$PATH"
herden --version
```

Already have the checkout? Start at `make host-check`. Source installation
writes the executable to `~/.local/bin`. It does not install plugins or change
your Claude, Codex, SSH or Tailscale configuration.

## Start and pair

Install and sign in to [Claude Code](https://code.claude.com/docs/en/quickstart)
or [Codex](https://developers.openai.com/codex/cli/) on the Host. Complete their
first-run login and directory-trust prompts there.

Start the persistent terminal:

```sh
herden
```

In an ordinary shell tab **inside that session**, run:

```sh
herden pair
```

From inside a running Herden session, press **Ctrl-B i** to show the same code
in a full-screen popup. Press Ctrl-C to close it. The shortcut is configurable
as `keys.pair`.

The command belongs in a shell, not an Agent's message field. A second Terminal
window under the same user also works. For a specific Tailscale address, use
`herden pair --address 100.64.1.2`, replacing the example address with yours.

Leave the QR code visible. On the iPhone, open **Herden → Hosts → Add Host**,
choose the scanner, allow the camera, and scan. Confirm the Host identity.
The app enrols its Device Key and connects. Choose or create a Space, then
use **+ → New Agent** to start Claude or Codex.

Each code expires after two minutes and enrols one phone. Run the command again
for another device. No Node, npm, plugin action or push relay is required.

## Troubleshooting

| Symptom | Next step |
| --- | --- |
| `herden: command not found` | Run `export PATH="$HOME/.local/bin:$PATH"` in this Terminal, or open a new terminal after installation. |
| Release download fails | Check access to `herden.3loc.ltd`, or use the source build above. |
| Expired QR code | Run `herden pair` again and keep its terminal open. |
| Host unreachable | Check Tailscale on both devices, the Host address, firewall and access policy. |
| Permission denied | Pair as the Host user running Herden; check Remote Login and whether Tailscale SSH is intercepting port 22. |
| Stream-local forwarding denied | Ask the administrator to enable OpenSSH Unix-socket forwarding. |
| Runtime unavailable | Run `herden` on the Host under the paired user. |
| Agent waiting on first launch | Finish its login or directory-trust dialogue on the Host. |

For a custom SSH port, add `--port 2222` to the pairing command, using the port
actually configured on your Host. Reconnection cannot wake a sleeping computer.
