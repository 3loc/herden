#!/bin/sh
set -eu

fail() { printf 'Herden release: %s\n' "$1" >&2; exit 1; }

[ "$#" -eq 3 ] \
    || fail 'usage: verify-host-release-asset.sh <binary> <version> <rust-target>'
binary=$1
version=$2
target=$3

[ -x "$binary" ] || fail "$binary is not executable"
if reported_version=$("$binary" --version 2>/dev/null); then
    [ "$reported_version" = "herden $version" ] \
        || fail "$binary reports '$reported_version', expected 'herden $version'"
else
    host=$(rustc -vV | awk '/^host:/ { print $2; exit }')
    [ "$target" != "$host" ] \
        || fail "$binary does not run on its native build machine"
    printf 'Cross-built %s; runtime version check deferred to a matching machine\n' "$target"
fi

command -v strings >/dev/null 2>&1 \
    || fail 'strings is required to verify Host release branding'
LC_ALL=C strings "$binary" | grep -Fq '[herden]' \
    || fail "$binary has no persistent Herden UI marker"

printf 'Verified Herden %s identity in %s\n' "$version" "$binary"
