#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)

# Run as an ordinary user: root login shells can reset HOME to /root, which
# would test the container account instead of each isolated shell fixture.
docker run --rm -i --platform linux/amd64 \
  -v "$repo_root:/src:ro" -w /src debian:bookworm-slim sh -s <<'SH'
set -eu
apt-get update -qq
apt-get install -y -qq --no-install-recommends bash zsh curl ca-certificates python3 shellcheck >/dev/null
useradd --create-home tester
shellcheck install.sh scripts/test-install.sh scripts/test-install-docker.sh
su -s /bin/sh tester -c 'bash scripts/test-install.sh && python3 scripts/test-install-path.py'
SH

# Also install the real published release with BusyBox sh, then repeat and
# confirm plain command lookup in both the current and a fresh login shell.
docker run --rm -i --platform linux/amd64 \
  -v "$repo_root:/src:ro" -w /src alpine:3.22 sh -s <<'SH'
set -eu
apk add --no-cache curl ca-certificates >/dev/null
adduser -D tester
cat > /tmp/herden-smoke.sh <<'SMOKE'
#!/bin/sh
set -eu
curl -fsSL file:///src/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
herden --version
herden pair --help >/dev/null
profile_digest=$(sha256sum "$HOME/.profile")
binary_digest=$(sha256sum "$HOME/.local/bin/herden")
sh /src/install.sh
test "$profile_digest" = "$(sha256sum "$HOME/.profile")"
test "$binary_digest" = "$(sha256sum "$HOME/.local/bin/herden")"
printf '%s\n' 'PASS public binary: fresh install, immediate command lookup, idempotent repeat'
SMOKE
su -s /bin/sh tester -c 'sh /tmp/herden-smoke.sh'
su -l -s /bin/sh tester -c 'herden --version && herden pair --help >/dev/null'
SH
