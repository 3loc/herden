#!/bin/sh
set -eu

fail() { printf 'Herden release: %s\n' "$1" >&2; exit 1; }

[ "$#" -eq 2 ] || fail 'usage: verify-host-release-asset.sh <binary> <version>'
binary=$1
version=$2

[ -x "$binary" ] || fail "$binary is not executable"
reported_version=$("$binary" --version 2>/dev/null) \
    || fail "$binary does not run on this build machine"
[ "$reported_version" = "herden $version" ] \
    || fail "$binary reports '$reported_version', expected 'herden $version'"

command -v strings >/dev/null 2>&1 \
    || fail 'strings is required to verify Host release branding'
LC_ALL=C strings "$binary" | grep -Fq '[herden]' \
    || fail "$binary has no persistent Herden UI marker"

printf 'Verified Herden %s identity in %s\n' "$version" "$binary"
