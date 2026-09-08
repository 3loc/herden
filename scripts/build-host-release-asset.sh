#!/bin/sh
set -eu

fail() { printf 'Herden release: %s\n' "$1" >&2; exit 1; }

[ "$#" -eq 2 ] || fail 'usage: build-host-release-asset.sh <rust-target> <output-directory>'
target=$1
output_dir=$2
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

case "$target" in
    x86_64-unknown-linux-musl) asset=herden-linux-x86_64 ;;
    aarch64-unknown-linux-musl) asset=herden-linux-aarch64 ;;
    x86_64-apple-darwin) asset=herden-macos-x86_64 ;;
    aarch64-apple-darwin) asset=herden-macos-aarch64 ;;
    *) fail "unsupported release target: $target" ;;
esac

command -v cargo >/dev/null 2>&1 || fail 'cargo is required'
command -v zig >/dev/null 2>&1 || fail 'Zig 0.15.2 is required'
[ "$(zig version)" = 0.15.2 ] || fail 'Zig 0.15.2 is required'
ZIG=${ZIG:-$(command -v zig)}
export ZIG

cd "$repo_dir/runtime"
rustup target add "$target"
if [ "$target" = aarch64-unknown-linux-musl ] || [ "$target" = x86_64-unknown-linux-musl ]; then
    command -v cargo-zigbuild >/dev/null 2>&1 \
        || fail 'cargo-zigbuild 0.23.4 is required for Linux release builds'
    [ "$(cargo-zigbuild -V)" = 'cargo-zigbuild 0.23.4' ] \
        || fail 'cargo-zigbuild 0.23.4 is required for the Linux ARM64 build'
    cargo zigbuild --release --locked --target "$target"
else
    cargo build --release --locked --target "$target"
fi

mkdir -p "$output_dir"
install -m 0755 "${CARGO_TARGET_DIR:-target}/$target/release/herden" "$output_dir/$asset"

version=$(awk -F'"' '/^version = "/ { print $2; exit }' Cargo.toml)
sh "$repo_dir/scripts/verify-host-release-asset.sh" \
    "$output_dir/$asset" "$version" "$target"

case "$target" in
    *-unknown-linux-musl)
        file "$output_dir/$asset" | grep -Eq 'statically linked|static-pie linked' \
            || fail "$asset is not statically linked"
        ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
    digest=$(sha256sum "$output_dir/$asset" | awk '{print $1}')
else
    digest=$(shasum -a 256 "$output_dir/$asset" | awk '{print $1}')
fi
printf '%s  %s\n' "$digest" "$asset" > "$output_dir/$asset.sha256"
printf 'Built %s\n' "$output_dir/$asset"
