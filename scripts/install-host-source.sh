#!/bin/sh
# The source path works before the first public Host binary release exists.
set -eu

fail() { printf 'Herden: %s\n' "$1" >&2; exit 1; }
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
install_dir=${HERDEN_INSTALL_DIR:-$HOME/.local/bin}

case "${1:-}" in
    ''|--check) ;;
    *) fail 'usage: sh scripts/install-host-source.sh [--check]' ;;
esac
case $(uname -s) in
    Linux|Darwin) ;;
    *) fail 'Host source installation supports Linux and macOS.' ;;
esac
for dependency in cargo cc; do
    command -v "$dependency" >/dev/null 2>&1 \
        || fail "Missing $dependency. Follow docs/guides/install-host.md, then retry."
done
zig_binary=${ZIG:-zig}
required_zig=$(sed -n 's/.*\.minimum_zig_version = "\([^"]*\)".*/\1/p' "$repo_dir/runtime/vendor/libghostty-vt/build.zig.zon")
[ -n "$required_zig" ] || fail 'vendored libghostty-vt does not declare its Zig version'
command -v "$zig_binary" >/dev/null 2>&1 \
    || fail "Install Zig $required_zig and put zig on PATH (or set ZIG to its full path)."
[ "$("$zig_binary" version)" = "$required_zig" ] \
    || fail "This Host needs Zig $required_zig. Other Zig versions are not supported."
printf 'Host build tools are available.\n'
[ "${1:-}" != --check ] || exit 0

cd "$repo_dir/runtime"
cargo build --release --locked
mkdir -p "$install_dir"
staged_binary=$(mktemp "$install_dir/.herden-install.XXXXXX")
trap 'rm -f "$staged_binary"' 0
trap 'exit 1' HUP INT TERM
install -m 0755 "${CARGO_TARGET_DIR:-target}/release/herden" "$staged_binary"
mv -f "$staged_binary" "$install_dir/herden"
printf '\nInstalled %s/herden\nNo plugins are required.\n\nStart your Host:\n  "%s/herden"\n\nIn a shell inside that session, pair your phone:\n  "%s/herden" pair\n' \
    "$install_dir" "$install_dir" "$install_dir"
