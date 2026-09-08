# Release the Herden Host

Herden Host releases are built on Linux and macOS machines and published at
`herden.3loc.ltd`. GitHub Actions are not part of this release path, and GitHub
does not host the binary assets.

Both builds use the repository Make target, which checks the pinned Zig version,
builds the selected Rust target and writes a SHA-256 checksum beside the binary.

For version `0.8.3`, create a release directory on the Linux build machine:

```sh
mkdir -p release/host-v0.8.3
make host-release-asset \
  TARGET=x86_64-unknown-linux-musl \
  OUT_DIR=release/host-v0.8.3
make host-release-asset \
  TARGET=aarch64-unknown-linux-musl \
  OUT_DIR=release/host-v0.8.3
```

Build both macOS assets from a clean checkout, placing their output in the same
release directory (copy the Linux artifacts there first if the machines do not
share storage):

```sh
make host-release-asset \
  TARGET=aarch64-apple-darwin \
  OUT_DIR=release/host-v0.8.3
make host-release-asset \
  TARGET=x86_64-apple-darwin \
  OUT_DIR=release/host-v0.8.3
```

Verify all four assets and assemble the release metadata:

```sh
make host-release-assemble \
  HOST_VERSION=0.8.3 \
  OUT_DIR=release/host-v0.8.3
```

Publish the assembled directory at
`https://herden.3loc.ltd/releases/host-v0.8.3/` using the production deployment
system. DNS, TLS, credentials and infrastructure configuration remain outside
this repository.

After deployment, verify the installer on both operating systems:

```sh
curl -fsSL https://herden.3loc.ltd/install.sh | sh
herden --version
```

Running the installer again verifies the published assets and leaves an
identical installed binary in place. Existing Herden server processes continue
running their current executable until they are restarted.
