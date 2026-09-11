#!/bin/sh
set -eu

binary="herden"
host_version="0.9.6"
host_tag="host-v${host_version}"
install_dir="${HERDEN_INSTALL_DIR:-$HOME/.local/bin}"
doc_dir="${HERDEN_DOC_DIR:-$HOME/.local/share/doc/herden}"
download_root="${HERDEN_DOWNLOAD_ROOT:-https://herden.3loc.ltd/releases/${host_tag}}"

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

# Quote a path as shell data, including spaces, apostrophes and metacharacters.
shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

configure_profile() {
    profile=$1
    # Recognize common existing PATH assignments without executing user startup
    # files. A mention in a comment is not configuration. The block we append
    # uses the same assignment, so repeated installation leaves the file alone.
    if [ -f "$profile" ] && HERDEN_PATH_QUOTED="$quoted_install_dir" awk '
        BEGIN {
            dirs[1] = ENVIRON["HERDEN_PATH_QUOTED"]
            if (ENVIRON["HERDEN_INSTALL_DIR"] == "" ||
                ENVIRON["HERDEN_INSTALL_DIR"] == ENVIRON["HOME"] "/.local/bin") {
                dirs[2] = "$HOME/.local/bin"
                dirs[3] = "${HOME}/.local/bin"
                dirs[4] = ENVIRON["HOME"] "/.local/bin"
            }
        }
        {
            sub(/^[ \t]+/, "")
            sub(/[ \t]+$/, "")
            sub(/^export[ \t]+/, "")
            for (i in dirs) {
                d = dirs[i]
                if ($0 == "PATH=" d ":$PATH" ||
                    $0 == "PATH=" d ":\"$PATH\"" ||
                    $0 == "PATH=\"" d ":$PATH\"" ||
                    $0 == "PATH=\"$PATH:" d "\"") found = 1
            }
        }
        END { exit !found }
    ' "$profile"; then
        return
    fi

    mkdir -p "$(dirname "$profile")"
    # shellcheck disable=SC2016 # Write literal variables for future shells.
    {
        printf '\n# Herden: make the Host command available in this shell.\n'
        printf 'case ":$PATH:" in\n'
        printf '    *:%s:*) ;;\n' "$quoted_install_dir"
        printf '    *)\n        export PATH=%s:"$PATH"\n        ;;\n' "$quoted_install_dir"
        printf 'esac\n'
    } >> "$profile" || fail "could not add Herden to PATH in ${profile}"
    log "configured PATH in ${profile}"
}

configure_path() {
    quoted_install_dir=$(shell_quote "$install_dir")
    case "${SHELL##*/}" in
        bash)
            # Bash reads only the first existing login file in this order.
            if [ -f "$HOME/.bash_profile" ]; then
                configure_profile "$HOME/.bash_profile"
            elif [ -f "$HOME/.bash_login" ]; then
                configure_profile "$HOME/.bash_login"
            else
                configure_profile "$HOME/.profile"
            fi
            configure_profile "$HOME/.bashrc"
            ;;
        zsh)
            configure_profile "${ZDOTDIR:-$HOME}/.zprofile"
            configure_profile "${ZDOTDIR:-$HOME}/.zshrc"
            ;;
        sh|dash|ash|ksh|'') configure_profile "$HOME/.profile" ;;
        *) warn "automatic PATH setup supports bash, zsh and POSIX shells; configure PATH in your ${SHELL} startup file" ;;
    esac

    # A piped installer cannot export into its parent Terminal. The quick-start
    # command sets PATH there; standalone callers get the same explicit step.
    case ":${PATH}:" in
        *":${install_dir}:"*) ;;
        *)
            # shellcheck disable=SC2016 # This command is for the parent shell.
            printf '\nTo use Herden in this Terminal now, run:\n\n  export PATH=%s:"$PATH"\n' "$quoted_install_dir"
            ;;
    esac
}

main() {
    need curl
    need awk
    need uname
    need mktemp
    need sed

    # PATH cannot represent directories containing a colon or newline.
    case "$install_dir" in
        /*) ;;
        *) fail "HERDEN_INSTALL_DIR must be an absolute path" ;;
    esac
    case "$install_dir" in
        *:*|*'
'*) fail "HERDEN_INSTALL_DIR cannot contain a colon or newline" ;;
    esac
    SHELL=${SHELL:-}

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
    staged=""
    updated=0
    previously_installed=0
    temporary="$(mktemp -d)"
    trap 'rm -rf "$temporary"; [ -z "$staged" ] || rm -f "$staged"' EXIT HUP INT TERM

    log "downloading ${asset} from ${host_tag}"
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 180 \
        "${download_root}/${asset}" -o "${temporary}/${binary}" \
        || fail "this release has no ${platform}/${architecture} Host binary"
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 \
        "${download_root}/${asset}.sha256" -o "${temporary}/${asset}.sha256" \
        || fail "this release has no checksum for ${asset}"
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 \
        "${download_root}/LICENSE" -o "${temporary}/LICENSE" \
        || fail "this release has no Apache-2.0 licence"
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 \
        "${download_root}/NOTICE" -o "${temporary}/NOTICE" \
        || fail "this release has no attribution notice"

    expected="$(awk '{print tolower($1); exit}' "${temporary}/${asset}.sha256")"
    actual="$(checksum "${temporary}/${binary}" | awk '{print tolower($1)}')"
    if [ "${#expected}" -ne 64 ] || [ "$actual" != "$expected" ]; then
        fail "the downloaded Herden binary failed checksum verification"
    fi
    mkdir -p "$install_dir"
    staged="$(mktemp "${install_dir}/.herden.XXXXXX")"
    cp "${temporary}/${binary}" "$staged"
    chmod 0755 "$staged"
    reported_version="$("$staged" --version 2>/dev/null)" \
        || fail "the downloaded Herden binary does not run on this Host"
    [ "$reported_version" = "herden ${host_version}" ] \
        || fail "the downloaded binary reports '${reported_version}', expected 'herden ${host_version}'"

    installed_digest=""
    if [ -f "${install_dir}/${binary}" ]; then
        previously_installed=1
        installed_digest="$(checksum "${install_dir}/${binary}" | awk '{print tolower($1)}')"
    fi
    if [ "$installed_digest" = "$actual" ]; then
        rm -f "$staged"
        staged=""
        log "${install_dir}/${binary} is already ${host_version}"
    else
        mv "$staged" "${install_dir}/${binary}"
        staged=""
        updated=1
        log "installed Herden ${host_version} at ${install_dir}/${binary}"
    fi

    mkdir -p "$doc_dir"
    mv "${temporary}/LICENSE" "${doc_dir}/LICENSE"
    mv "${temporary}/NOTICE" "${doc_dir}/NOTICE"
    log "installed licence and attribution in ${doc_dir}"

    if [ "${HERDEN_INSTALL_NOTIFICATIONS:-0}" = "1" ]; then
        if command -v git >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
            log "installing encrypted notification support"
            "${install_dir}/${binary}" plugin install 3loc/herden/plugin --ref "$host_tag" --yes \
                || warn "notification support could not be installed; the Host runtime is ready"
        else
            warn "notifications need git and npm; install them, then run:"
            warn "\"${install_dir}/${binary}\" plugin install 3loc/herden/plugin --ref ${host_tag} --yes"
        fi
    fi

    configure_path

    if command -v sshd >/dev/null 2>&1; then
        log "OpenSSH Server is installed"
    else
        warn "install and enable OpenSSH Server before pairing this Host"
    fi

    if [ "$updated" -eq 1 ] && [ "$previously_installed" -eq 1 ]; then
        warn "an already-open Herden client keeps its old code until you detach and relaunch it"
        warn "update a running server without dropping sessions:"
        warn "\"${install_dir}/${binary}\" server live-handoff --import-exe \"${install_dir}/${binary}\""
    fi

    current_runtime=${HERDR_BIN_PATH:-}
    current_socket=${HERDR_SOCKET_PATH:-}
    if [ "${HERDR_ENV:-0}" = "1" ] && {
        [ "${current_runtime##*/}" = "herdr" ] \
            || [ "${current_socket#*/.config/herdr/}" != "$current_socket" ];
    }; then
        warn "this installer is running inside an existing upstream Herdr session"
        warn "installing Herden cannot rename or replace that running Herdr client"
        warn "detach with Ctrl-B, then q; from the outer shell run:"
        warn "\"${install_dir}/${binary}\""
    fi

    printf '\nHerden %s is ready.\n\nStart or reattach:\n\n  herden\n\nDisplay a Pairing Code from a shell:\n\n  herden pair\n\nAlready inside Herden? Press Ctrl-B, then i.\n\n' "$host_version"
}

main "$@"
