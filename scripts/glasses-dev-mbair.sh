#!/bin/sh
# Start the developer-only Even simulator in Ted's logged-in macOS session.
# It owns only its cache directory and never prints HUD credentials.
set -eu

action=${1:-open}
host=${GLASSES_DEV_HOST:-mbair}
# shellcheck disable=SC1007  # CDPATH= is an intentional empty assignment.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC2016  # $HOME must expand on the remote host, not here.
remote_runtime='$HOME/.cache/herden-glasses-runtime'

install_token() {
  source_host=$1
  token_file=$2
  # shellcheck disable=SC2029  # $HOME inside $remote_runtime is meant to expand remotely.
  if ssh "$host" "test -s $remote_runtime/$token_file"; then
    return
  fi
  # The token travels over SSH stdin and is written directly with 0600 mode.
  # Do not assign it to a local variable or print it in diagnostics.
  # shellcheck disable=SC2029  # $HOME inside $remote_runtime is meant to expand remotely.
  ssh "$source_host" 'herden glasses token show | tail -n 1' |
    ssh "$host" "umask 077; mkdir -p $remote_runtime; cat > $remote_runtime/$token_file; chmod 600 $remote_runtime/$token_file"
}

case "$action" in
  status)
    ssh "$host" '/bin/sh -s' <<'REMOTE'
set -eu
runtime="$HOME/.cache/herden-glasses-runtime"
app="$HOME/.cache/herden-glasses-simulator"
for name in tunnel vite simulator; do
  file="$runtime/$name.pid"
  if [ -f "$file" ] && kill -0 "$(cat "$file")" 2>/dev/null; then
    printf '%-16s running (pid %s)\n' "$name" "$(cat "$file")"
  else
    printf '%-16s stopped\n' "$name"
  fi
done
test -d "$app" || true
REMOTE
    ;;
  stop)
    ssh "$host" '/bin/sh -s' <<'REMOTE'
set -eu
runtime="$HOME/.cache/herden-glasses-runtime"
app="$HOME/.cache/herden-glasses-simulator"
for name in simulator vite tunnel fansvine-tunnel; do
  file="$runtime/$name.pid"
  if [ -f "$file" ]; then
    kill -TERM "$(cat "$file")" 2>/dev/null || true
    rm -f "$file"
  fi
done
for pattern in "$app/node_modules/@evenrealities/sim-darwin-arm64/bin/evenhub-simulator" "$app/node_modules/.bin/vite --host 127.0.0.1"; do
  for pid in $(pgrep -f "$pattern" 2>/dev/null || true); do kill -TERM "$pid" 2>/dev/null || true; done
done
echo "stopped the tracked mbair HUD simulator, Vite, and tunnels"
REMOTE
    ;;
  open|refresh)
    install_token 3loc hud-token
    install_token fansvine fansvine-hud-token
    rsync -a --delete --exclude node_modules --exclude dist "$root/glasses/app/" "$host:~/.cache/herden-glasses-simulator/"
    ssh "$host" '/bin/sh -s' <<'REMOTE'
set -eu
runtime="$HOME/.cache/herden-glasses-runtime"
logs="$HOME/.cache/herden-glasses-logs"
app="$HOME/.cache/herden-glasses-simulator"
mkdir -p "$runtime" "$logs"
node_bin=$(find "$HOME/.nvm/versions/node" -type f -path '*/bin/node' -print 2>/dev/null | sort | tail -n 1 | xargs -n 1 dirname)
test -n "$node_bin" || { echo "Node is not installed for mbair" >&2; exit 1; }
export PATH="$node_bin:$PATH"
command -v npm >/dev/null
for required in "$runtime/hud-token" "$runtime/fansvine-hud-token"; do
  test -s "$required" || { echo "missing $required" >&2; exit 1; }
done
stop_pid() {
  file="$runtime/$1.pid"
  if [ -f "$file" ]; then
    kill -TERM "$(cat "$file")" 2>/dev/null || true
    rm -f "$file"
  fi
}
stop_matching() {
  pattern=$1
  for pid in $(pgrep -f "$pattern" 2>/dev/null || true); do kill -TERM "$pid" 2>/dev/null || true; done
  sleep 1
  for pid in $(pgrep -f "$pattern" 2>/dev/null || true); do kill -KILL "$pid" 2>/dev/null || true; done
}
for name in simulator vite tunnel fansvine-tunnel; do stop_pid "$name"; done
stop_matching "$app/node_modules/@evenrealities/sim-darwin-arm64/bin/evenhub-simulator"
stop_matching "$app/node_modules/.bin/vite --host 127.0.0.1"
sleep 1
start_tunnel() {
  name=$1
  port=$2
  target_host=$3
  target_address=$4
  nohup ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
    -L "127.0.0.1:$port:$target_address" "$target_host" >"$logs/$name.log" 2>&1 < /dev/null &
  echo $! > "$runtime/$name.pid"
  sleep 1
  kill -0 "$(cat "$runtime/$name.pid")" 2>/dev/null || { cat "$logs/$name.log" >&2; exit 1; }
}
# mbair cannot currently route directly to 3loc's HUD address. Keep that Host
# behind a loopback tunnel; its direct Tailnet route to fansvine is healthy.
start_tunnel tunnel 18791 3loc 100.64.0.2:8791
if [ ! -d "$app/node_modules/@evenrealities/evenhub-simulator" ]; then
  npm --prefix "$app" ci >"$logs/npm-install.log" 2>&1
fi
proxy_hosts='[{"id":"development-3loc","name":"3loc","baseUrl":"http://localhost:5173/hud","token":"development-proxy"},{"id":"development-fansvine","name":"fansvine","baseUrl":"http://localhost:5173/hud/fansvine","token":"development-proxy"}]'
nohup env HERDEN_HUD_PROXY_TARGET=http://127.0.0.1:18791 HERDEN_HUD_PROXY_TOKEN_FILE="$runtime/hud-token" HERDEN_HUD_PROXY_FANSVINE_TARGET=http://100.114.152.109:8791 HERDEN_HUD_PROXY_FANSVINE_TOKEN_FILE="$runtime/fansvine-hud-token" VITE_HERDEN_HUD_PROXY=1 VITE_HERDEN_HUD_PROXY_HOSTS="$proxy_hosts" npm --prefix "$app" run dev -- --host 127.0.0.1 >"$logs/vite.log" 2>&1 < /dev/null &
echo $! > "$runtime/vite.pid"
sleep 2
curl -fsS --max-time 3 http://127.0.0.1:5173/hud/health >/dev/null
curl -fsS --max-time 3 http://127.0.0.1:5173/hud/fansvine/health >/dev/null
nohup npm --prefix "$app" run sim -- --automation-port 8792 >"$logs/simulator.log" 2>&1 < /dev/null &
echo $! > "$runtime/simulator.pid"
sleep 3
kill -0 "$(cat "$runtime/simulator.pid")" 2>/dev/null || { cat "$logs/simulator.log" >&2; exit 1; }
echo "Herden HUD simulator is open on mbair."
REMOTE
    ;;
  *)
    echo "usage: $0 {open|refresh|status|stop}" >&2
    exit 2
    ;;
esac
