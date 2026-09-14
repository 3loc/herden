# Herden Host runtime

This directory contains the native Host component of Herden. It keeps coding
agents and their terminals alive, exposes the socket API used by the iOS app,
and provides the `herden` command-line interface.

The runtime is derived from pristine upstream
[`herdrdev/herdr`](https://github.com/herdrdev/herdr), without the private
3LOC Herdr customizations. See [UPSTREAM.md](UPSTREAM.md) for the exact source
baseline and licensing details.

## Develop

The pinned Rust and Zig versions are recorded in `rust-toolchain.toml` and
`.zigversion`.

```sh
cargo build
cargo test --locked
cargo run -- pair
```

The production executable and all user-facing commands are named `herden`.
The legacy `HERDR_*` protocol environment variables and wire field names are
retained where changing them would break compatible integrations or existing
iOS Pairing Codes.

When already inside Herden, press `Ctrl-B i` to open a short-lived Pairing Code
in a full-screen popup. Close the popup with `Ctrl-C`; change or disable the
binding with `keys.pair`.
