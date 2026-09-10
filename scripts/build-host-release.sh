#!/bin/sh
set -eu

fail() { printf 'Herden release: %s\n' "$1" >&2; exit 1; }

[ "$#" -eq 2 ] \
    || fail 'usage: build-host-release.sh <version> <output-directory>'
version=$1
output_dir=$2
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

case "$version" in
    *[!0-9.]*|.*|*.) fail "invalid Host version: $version" ;;
esac
[ "$(printf '%s' "$version" | awk -F. '{print NF}')" -eq 3 ] \
    || fail "invalid Host version: $version"

source_version=$(awk -F'"' '/^version = "/ { print $2; exit }' "$repo_dir/runtime/Cargo.toml")
[ "$source_version" = "$version" ] \
    || fail "runtime version is $source_version, not requested $version"

mkdir -p "$output_dir"
output_dir=$(CDPATH='' cd -- "$output_dir" && pwd)

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

sha256_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

set -- runtime Makefile \
    scripts/build-host-release.sh \
    scripts/build-host-release-asset.sh \
    scripts/verify-host-release-asset.sh \
    scripts/assemble-host-release.sh
if command -v git >/dev/null 2>&1 \
    && git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && [ -z "$(git -C "$repo_dir" status --porcelain --untracked-files=all -- "$@")" ]
then
    source_manifest=$(
        git -C "$repo_dir" ls-tree -r HEAD -- "$@" \
            | sha256_stdin
    )
else
    source_manifest=$(
        cd "$repo_dir"
        {
            find runtime -type f \
                ! -path 'runtime/target/*' \
                ! -path 'runtime/.zig-global-cache/*' \
                ! -path 'runtime/vendor/libghostty-vt/zig-out/*' \
                ! -path 'runtime/vendor/libghostty-vt/.zig-cache/*' \
                -print
            printf '%s\n' Makefile \
                scripts/build-host-release.sh \
                scripts/build-host-release-asset.sh \
                scripts/verify-host-release-asset.sh \
                scripts/assemble-host-release.sh
        } | LC_ALL=C sort | while IFS= read -r source_file; do
            printf '%s  %s\n' "$(sha256_file "$source_file")" "$source_file"
        done | sha256_stdin
    )
fi
receipt="$output_dir/.host-release-input.sha256"
if [ -f "$receipt" ]; then
    recorded_manifest=$(awk 'NR == 1 { print $1 }' "$receipt")
    [ "$recorded_manifest" = "$source_manifest" ] \
        || fail "release directory belongs to source $recorded_manifest, not $source_manifest"
else
    for asset in \
        herden-linux-x86_64 herden-linux-aarch64 \
        herden-macos-x86_64 herden-macos-aarch64
    do
        if [ -e "$output_dir/$asset" ] || [ -e "$output_dir/$asset.sha256" ]; then
            fail "release directory contains assets but no source receipt: $output_dir"
        fi
    done
    printf '%s  source-inputs\n' "$source_manifest" > "$receipt"
fi

asset_is_reusable() {
    target=$1
    asset=$2
    binary="$output_dir/$asset"
    checksum="$binary.sha256"

    [ -f "$binary" ] && [ -f "$checksum" ] || return 1
    expected=$(awk 'NR == 1 { print $1 }' "$checksum")
    [ -n "$expected" ] || return 1
    [ "$(sha256_file "$binary")" = "$expected" ] || return 1
    chmod 0755 "$binary"
    sh "$repo_dir/scripts/verify-host-release-asset.sh" \
        "$binary" "$version" "$target" >/dev/null
    case "$target" in
        *-unknown-linux-musl)
            file "$binary" | grep -Eq 'statically linked|static-pie linked' || return 1
            ;;
    esac
}

for spec in \
    x86_64-unknown-linux-musl:herden-linux-x86_64 \
    aarch64-unknown-linux-musl:herden-linux-aarch64 \
    x86_64-apple-darwin:herden-macos-x86_64 \
    aarch64-apple-darwin:herden-macos-aarch64
do
    target=${spec%%:*}
    asset=${spec#*:}
    if asset_is_reusable "$target" "$asset"; then
        printf 'Reusing verified %s\n' "$output_dir/$asset"
    else
        sh "$repo_dir/scripts/build-host-release-asset.sh" "$target" "$output_dir"
    fi
done

sh "$repo_dir/scripts/assemble-host-release.sh" "$version" "$output_dir"
printf 'Host %s release assets are complete in %s\n' "$version" "$output_dir"
