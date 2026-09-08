#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/herden-install-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT HUP INT TERM

cmp -s "$repo_root/install.sh" "$repo_root/landing/public/install.sh" || {
  echo 'landing/public/install.sh must match the root installer' >&2
  exit 1
}

mkdir -p "$fixture/bin" "$fixture/home" "$fixture/install" "$fixture/doc"

cat > "$fixture/bin/uname" <<'SH'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' Linux ;;
  -m) printf '%s\n' x86_64 ;;
  *) exit 2 ;;
esac
SH

cat > "$fixture/bin/curl" <<'SH'
#!/bin/sh
output=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output=$2; shift 2 ;;
    -*) shift ;;
    *) url=$1; shift ;;
  esac
done
case "$url" in
  */herden-linux-x86_64)
    cat > "$output" <<'BIN'
#!/bin/sh
if [ "${1:-}" = --version ]; then
  if [ "${HERDEN_TEST_WRONG_VERSION:-0}" = 1 ]; then
    printf '%s\n' 'herden 9.9.9'
  else
    printf '%s\n' 'herden 0.9.0'
  fi
  exit 0
fi
if [ "${1:-}" = plugin ]; then
  printf '%s\n' "$*" > "$HERDEN_TEST_PLUGIN_LOG"
fi
BIN
    ;;
  */herden-linux-x86_64.sha256)
    digest=$(/usr/bin/sha256sum "$(dirname "$output")/herden" | /usr/bin/awk '{print $1}')
    if [ "${HERDEN_TEST_BAD_CHECKSUM:-0}" = 1 ]; then
      digest=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    fi
    printf '%s  %s\n' "$digest" herden-linux-x86_64 > "$output"
    ;;
  */LICENSE)
    printf '%s\n' 'Apache License 2.0 test fixture' > "$output"
    ;;
  */NOTICE)
    printf '%s\n' 'Herden upstream attribution test fixture' > "$output"
    ;;
  *) exit 22 ;;
esac
SH

cat > "$fixture/bin/git" <<'SH'
#!/bin/sh
exit 0
SH

cat > "$fixture/bin/npm" <<'SH'
#!/bin/sh
exit 0
SH

chmod 0755 "$fixture/bin/uname" "$fixture/bin/curl" "$fixture/bin/git" "$fixture/bin/npm"
run_installer() {
  env HOME="$fixture/home" SHELL=/bin/bash sh "$repo_root/install.sh"
}
export PATH="$fixture/bin:/usr/bin:/bin"
export HERDEN_INSTALL_DIR="$fixture/install"
export HERDEN_DOC_DIR="$fixture/doc"
export HERDEN_TEST_PLUGIN_LOG="$fixture/plugin.log"
unset HERDR_ENV HERDR_BIN_PATH HERDR_SOCKET_PATH

run_installer > "$fixture/install.out" 2> "$fixture/install.err"
test -x "$fixture/install/herden"
test -s "$fixture/doc/LICENSE"
test -s "$fixture/doc/NOTICE"
test ! -e "$fixture/plugin.log"
grep -Fq "Herden 0.9.0 is ready" "$fixture/install.out"
grep -Fq "Start or reattach" "$fixture/install.out"
grep -Fq '  herden pair' "$fixture/install.out"
grep -Fq "Already inside Herden? Press Ctrl-B, then i." "$fixture/install.out"
test "$("$fixture/install/herden" --version)" = 'herden 0.9.0'

HERDR_ENV=1 \
HERDR_BIN_PATH="$fixture/legacy/bin/herdr" \
HERDR_SOCKET_PATH="$fixture/legacy/.config/herdr/herdr.sock" \
    run_installer > "$fixture/legacy.out" 2> "$fixture/legacy.err"
grep -Fq 'inside an existing upstream Herdr session' "$fixture/legacy.err"
grep -Fq 'cannot rename or replace that running Herdr client' "$fixture/legacy.err"
grep -Fq 'detach with Ctrl-B, then d' "$fixture/legacy.err"
grep -Fq "\"$fixture/install/herden\"" "$fixture/legacy.err"

if grep -Fq 'detach and relaunch' "$fixture/install.err"; then
  echo 'fresh install printed upgrade instructions' >&2
  exit 1
fi

HERDEN_INSTALL_NOTIFICATIONS=1 run_installer > "$fixture/optional.out" 2> "$fixture/optional.err"
grep -Fq 'is already 0.9.0' "$fixture/optional.out"
grep -Fqx 'plugin install 3loc/herden/plugin --ref host-v0.9.0 --yes' "$fixture/plugin.log"

printf '%s\n' '#!/bin/sh' 'printf "%s\n" "herden 0.8.3"' > "$fixture/install/herden"
chmod 0755 "$fixture/install/herden"
run_installer > "$fixture/upgrade.out" 2> "$fixture/upgrade.err"
grep -Fq 'detach and relaunch' "$fixture/upgrade.err"
grep -Fq "server live-handoff --import-exe \"$fixture/install/herden\"" "$fixture/upgrade.err"
test "$("$fixture/install/herden" --version)" = 'herden 0.9.0'

bad_install="$fixture/bad-install"
mkdir -p "$bad_install"
if HERDEN_INSTALL_DIR="$bad_install" HERDEN_TEST_BAD_CHECKSUM=1 \
    run_installer > "$fixture/bad.out" 2> "$fixture/bad.err"; then
  echo 'installer accepted a corrupt checksum' >&2
  exit 1
fi
test ! -e "$bad_install/herden"
grep -Fq 'failed checksum verification' "$fixture/bad.err"

wrong_version_install="$fixture/wrong-version-install"
mkdir -p "$wrong_version_install"
if HERDEN_INSTALL_DIR="$wrong_version_install" HERDEN_TEST_WRONG_VERSION=1 \
    run_installer > "$fixture/wrong-version.out" 2> "$fixture/wrong-version.err"; then
  echo 'installer accepted a binary with the wrong version' >&2
  exit 1
fi
test ! -e "$wrong_version_install/herden"
grep -Fq "expected 'herden 0.9.0'" "$fixture/wrong-version.err"

echo 'installer behavior passed'
