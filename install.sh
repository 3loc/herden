#!/bin/sh
set -eu

binary="herden"
host_version="0.8.2"
host_tag="host-v${host_version}"
install_dir="${HERDEN_INSTALL_DIR:-$HOME/.local/bin}"
download_root="${HERDEN_DOWNLOAD_ROOT:-https://herden.austrheim.ca7.fm/downloads/${host_tag}}"

log() { printf '  \033[32m>\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1" >&2; }
fail() { printf '  \033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || fail "Herden installation requires $1"
}

checksum() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        fail "checksum verification requires sha256sum, shasum, or openssl"
    fi
}

main() {
    need curl
    need awk
    need uname
    need mktemp

    case "$(uname -s)" in
        Linux) platform="linux" ;;
        Darwin) platform="macos" ;;
        *) fail "Herden supports Linux and macOS Hosts" ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) architecture="x86_64" ;;
        arm64|aarch64) architecture="aarch64" ;;
        *) fail "unsupported CPU architecture: $(uname -m)" ;;
    esac

    asset="herden-${platform}-${architecture}"
    temporary="$(mktemp -d)"
    trap 'rm -rf "$temporary"' EXIT HUP INT TERM

    log "downloading ${asset} from ${host_tag}"
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 180 \
        "${download_root}/${asset}" -o "${temporary}/${binary}" \
        || fail "this release has no ${platform}/${architecture} Host binary"
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 \
        "${download_root}/${asset}.sha256" -o "${temporary}/${asset}.sha256" \
        || fail "this release has no checksum for ${asset}"

    expected="$(awk '{print tolower($1); exit}' "${temporary}/${asset}.sha256")"
    actual="$(checksum "${temporary}/${binary}" | awk '{print tolower($1)}')"
    if [ "${#expected}" -ne 64 ] || [ "$actual" != "$expected" ]; then
        fail "the downloaded Herden binary failed checksum verification"
    fi

    mkdir -p "$install_dir"
    chmod 0755 "${temporary}/${binary}"
    mv "${temporary}/${binary}" "${install_dir}/${binary}"
    log "installed ${install_dir}/${binary}"

    if [ "${HERDEN_INSTALL_NOTIFICATIONS:-0}" = "1" ]; then
        if command -v git >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
            log "installing encrypted notification support"
            "${install_dir}/${binary}" plugin install 3loc/herden/plugin --ref "$host_tag" --yes \
                || warn "notification support could not be installed; the Host runtime is ready"
        else
            warn "notifications need git and npm; install them, then run:"
            warn "herden plugin install 3loc/herden/plugin --ref ${host_tag} --yes"
        fi
    fi

    case ":${PATH}:" in
        *":${install_dir}:"*) ;;
        *)
            warn "${install_dir} is not on PATH"
            warn "add this to your shell profile: export PATH=\"${install_dir}:\$PATH\""
            ;;
    esac

    if command -v sshd >/dev/null 2>&1; then
        log "OpenSSH Server is available"
    else
        warn "enable OpenSSH Server before pairing this Host"
    fi

    printf '\nHerden is ready. Display a Pairing Code with:\n\n  "%s/herden" pair\n\n' "$install_dir"
}

main "$@"
