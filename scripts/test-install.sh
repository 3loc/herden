#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/herden-install-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT HUP INT TERM

mkdir -p "$fixture/bin" "$fixture/home" "$fixture/install"

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
  */releases/tags/host-v0.8.2)
    printf '%s\n' '{"tag_name":"host-v0.8.2"}'
    ;;
  */herden-linux-x86_64)
    cat > "$output" <<'BIN'
#!/bin/sh
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
  *) exit 22 ;;
esac
SH

chmod 0755 "$fixture/bin/uname" "$fixture/bin/curl"
export HOME="$fixture/home"
export PATH="$fixture/bin:/usr/bin:/bin"
export HERDEN_INSTALL_DIR="$fixture/install"
export HERDEN_TEST_PLUGIN_LOG="$fixture/plugin.log"

sh "$repo_root/install.sh" > "$fixture/install.out" 2> "$fixture/install.err"
test -x "$fixture/install/herden"
test ! -e "$fixture/plugin.log"
grep -Fq "\"$fixture/install/herden\" pair" "$fixture/install.out"

HERDEN_INSTALL_NOTIFICATIONS=1 sh "$repo_root/install.sh" > "$fixture/optional.out" 2> "$fixture/optional.err"
grep -Fqx 'plugin install 3loc/herden/plugin --ref host-v0.8.2 --yes' "$fixture/plugin.log"

bad_install="$fixture/bad-install"
mkdir -p "$bad_install"
if HERDEN_INSTALL_DIR="$bad_install" HERDEN_TEST_BAD_CHECKSUM=1 \
    sh "$repo_root/install.sh" > "$fixture/bad.out" 2> "$fixture/bad.err"; then
  echo 'installer accepted a corrupt checksum' >&2
  exit 1
fi
test ! -e "$bad_install/herden"
grep -Fq 'failed checksum verification' "$fixture/bad.err"

echo 'installer behavior passed'
