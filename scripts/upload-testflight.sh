#!/usr/bin/env bash

# Export an existing archive to App Store Connect. Authentication is either
# supplied explicitly through App Store Connect API-key environment variables
# or delegated to the Apple account configured in Xcode.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Xcode's packaging pipeline starts an rsync server through PATH. Homebrew's
# rsync does not understand the Apple-specific flags used by /usr/bin/rsync,
# so keep the system toolchain first even when Infisical came from Homebrew.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

archive_path="${ARCHIVE_PATH:-build/Herden.xcarchive}"
export_path="${EXPORT_PATH:-build/export}"
export_options="${EXPORT_OPTIONS_PATH:-scripts/ExportOptions.plist}"

die() { printf 'upload: %s\n' "$*" >&2; exit 1; }

[ -d "$archive_path" ] || die "archive not found at $archive_path (run: make archive)"
[ -f "$export_options" ] || die "export options not found at $export_options"

key_id="${APP_STORE_CONNECT_KEY_ID:-}"
issuer_id="${APP_STORE_CONNECT_ISSUER_ID:-}"
key_base64="${APP_STORE_CONNECT_PRIVATE_KEY_P8_BASE64:-}"
key_path="${APP_STORE_CONNECT_PRIVATE_KEY_PATH:-}"
temporary_key=""
temporary_directory=""

cleanup() {
    if [ -n "$temporary_key" ]; then
        rm -f "$temporary_key"
    fi
    if [ -n "$temporary_directory" ]; then
        rmdir "$temporary_directory" 2>/dev/null || true
    fi
}
trap cleanup EXIT

auth_args=()
if [ -n "$key_id$issuer_id$key_base64$key_path" ]; then
    [ -n "$key_id" ] || die "APP_STORE_CONNECT_KEY_ID is required for API-key authentication"
    [ -n "$issuer_id" ] || die "APP_STORE_CONNECT_ISSUER_ID is required for API-key authentication"
    if [ -n "$key_base64" ] && [ -n "$key_path" ]; then
        die "set only one of APP_STORE_CONNECT_PRIVATE_KEY_P8_BASE64 or APP_STORE_CONNECT_PRIVATE_KEY_PATH"
    fi

    if [ -n "$key_base64" ]; then
        temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/herden-upload.XXXXXX")"
        chmod 700 "$temporary_directory"
        temporary_key="$temporary_directory/AuthKey_${key_id}.p8"
        printf '%s' "$key_base64" | openssl base64 -d -A >"$temporary_key" \
            || die "APP_STORE_CONNECT_PRIVATE_KEY_P8_BASE64 is not valid base64"
        chmod 600 "$temporary_key"
        key_path="$temporary_key"
    fi

    [ -n "$key_path" ] || die "an App Store Connect private key is required for API-key authentication"
    [ -f "$key_path" ] || die "App Store Connect private key not found at $key_path"
    grep -q '^-----BEGIN PRIVATE KEY-----$' "$key_path" \
        || die "App Store Connect private key is not a valid .p8 file"

    auth_args=(
        -authenticationKeyPath "$key_path"
        -authenticationKeyID "$key_id"
        -authenticationKeyIssuerID "$issuer_id"
    )
    echo "==> Uploading with App Store Connect API key $key_id"
else
    echo "==> Uploading with the Apple account configured in Xcode"
fi

xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportOptionsPlist "$export_options" \
    -exportPath "$export_path" \
    -allowProvisioningUpdates \
    "${auth_args[@]}"
