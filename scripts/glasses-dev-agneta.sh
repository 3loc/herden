#!/bin/sh
# Start and inspect the developer-only Even simulator on Agneta.
# Credentials stay in 0600 files on Agneta; this script never reads or prints
# them. It deliberately manages only processes recorded in its runtime folder.
set -eu

action=${1:-open}
host=${GLASSES_DEV_HOST:-agneta}
# shellcheck disable=SC1007  # CDPATH= is an intentional empty assignment.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

case "$action" in
  status)
    ssh "$host" 'zsh -s' <<'REMOTE'
set -eu
runtime="$HOME/.cache/herden-glasses-runtime"
app="$HOME/.cache/herden-glasses-simulator"
for name in tunnel fansvine-tunnel; do
  file="$runtime/$name.pid"
  if [ -f "$file" ] && kill -0 "$(cat "$file")" 2>/dev/null; then
    printf '%-16s running (pid %s)\n' "$name" "$(cat "$file")"
  else
    printf '%-16s stopped\n' "$name"
  fi
done
for name in vite simulator; do
  case "$name" in
    vite) pattern="$app/node_modules/.bin/vite --host 127.0.0.1" ;;
    simulator) pattern="$app/node_modules/@evenrealities/sim-linux-x64/bin/evenhub-simulator" ;;
  esac
  pid=$(pgrep -f "$pattern" | tail -n 1 || true)
  if [ -n "$pid" ]; then printf '%-16s running (pid %s)\n' "$name" "$pid"; else printf '%-16s stopped\n' "$name"; fi
done
REMOTE
    ;;
  stop)
    ssh "$host" 'zsh -s' <<'REMOTE'
set -eu
app="$HOME/.cache/herden-glasses-simulator"
stop_matching() {
  pattern="$1"
  for pid in $(pgrep -f "$pattern" || true); do kill -TERM "$pid" 2>/dev/null || true; done
  sleep 1
  for pid in $(pgrep -f "$pattern" || true); do kill -KILL "$pid" 2>/dev/null || true; done
}
stop_matching "$app/node_modules/@evenrealities/sim-linux-x64/bin/evenhub-simulator"
stop_matching "$app/node_modules/.bin/vite --host 127.0.0.1"
echo "stopped every HUD simulator and Vite process under $app"
REMOTE
    ;;
  screenshot)
    ssh "$host" 'zsh -s' <<'REMOTE'
set -eu
runtime="$HOME/.cache/herden-glasses-runtime"
app="$HOME/.cache/herden-glasses-simulator"
pid=$(pgrep -f "$app/node_modules/@evenrealities/sim-linux-x64/bin/evenhub-simulator" | tail -n 1 || true)
kill -0 "$pid" 2>/dev/null || { echo "simulator is not running; use make glasses-open" >&2; exit 1; }
env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus WAYLAND_DISPLAY=wayland-0 grim /tmp/herden-glasses-latest.png
REMOTE
    scp "$host:/tmp/herden-glasses-latest.png" /vm-share/screenshots/herden-glasses-latest.png
    printf '%s\n' '/vm-share/screenshots/herden-glasses-latest.png'
    ;;
  input)
    input=${2:-}
    case "$input" in up|down|click|double_click) ;; *)
      echo "use GLASSES_INPUT=up, down, click, or double_click" >&2
      exit 2
    esac
    # shellcheck disable=SC2029  # "$input" is validated above and passed as an argument on purpose.
    ssh "$host" 'zsh -s' "$input" <<'REMOTE'
set -eu
input=$1
runtime="$HOME/.cache/herden-glasses-runtime"
app="$HOME/.cache/herden-glasses-simulator"
pid=$(pgrep -f "$app/node_modules/@evenrealities/sim-linux-x64/bin/evenhub-simulator" | tail -n 1 || true)
kill -0 "$pid" 2>/dev/null || { echo "simulator is not running; use make glasses-open" >&2; exit 1; }
curl -fsS --max-time 3 -X POST http://127.0.0.1:8792/api/input \
  -H 'content-type: application/json' --data "{\"action\":\"$input\"}" >/dev/null
echo "sent $input"
REMOTE
    ;;
  open|refresh)
    rsync -a --delete --exclude node_modules --exclude dist "$root/glasses/app/" "$host:~/.cache/herden-glasses-simulator/"
    ssh "$host" 'zsh -s' <<'REMOTE'
set -eu
runtime="$HOME/.cache/herden-glasses-runtime"
logs="$HOME/.cache/herden-glasses-logs"
app="$HOME/.cache/herden-glasses-simulator"
stop_matching() {
  pattern="$1"
  for pid in $(pgrep -f "$pattern" || true); do kill -TERM "$pid" 2>/dev/null || true; done
  sleep 1
  for pid in $(pgrep -f "$pattern" || true); do kill -KILL "$pid" 2>/dev/null || true; done
}
for required in "$runtime/tunnel.pid" "$runtime/fansvine-tunnel.pid" "$runtime/hud-token" "$runtime/fansvine-hud-token"; do
  [ -e "$required" ] || { echo "missing $required; set up the private HUD tunnels first" >&2; exit 1; }
done
stop_matching "$app/node_modules/@evenrealities/sim-linux-x64/bin/evenhub-simulator"
stop_matching "$app/node_modules/.bin/vite --host 127.0.0.1"
proxy_hosts='[{"id":"development-3loc","name":"3loc","baseUrl":"http://localhost:5173/hud","token":"development-proxy"},{"id":"development-fansvine","name":"fansvine","baseUrl":"http://localhost:5173/hud/fansvine","token":"development-proxy"}]'
nohup env HERDEN_HUD_PROXY_TARGET=http://127.0.0.1:18791 HERDEN_HUD_PROXY_TOKEN_FILE="$runtime/hud-token" HERDEN_HUD_PROXY_FANSVINE_TARGET=http://127.0.0.1:18792 HERDEN_HUD_PROXY_FANSVINE_TOKEN_FILE="$runtime/fansvine-hud-token" VITE_HERDEN_HUD_PROXY=1 VITE_HERDEN_HUD_PROXY_HOSTS="$proxy_hosts" npm --prefix "$app" run dev -- --host 127.0.0.1 >"$logs/vite.log" 2>&1 < /dev/null &
echo $! > "$runtime/vite.pid"
sleep 2
curl -fsS --max-time 3 http://127.0.0.1:5173/hud/health >/dev/null
curl -fsS --max-time 3 http://127.0.0.1:5173/hud/fansvine/health >/dev/null
nohup env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 npm --prefix "$app" run sim -- --automation-port 8792 >"$logs/simulator.log" 2>&1 < /dev/null &
sleep 3
vite_pid=$(pgrep -f "$app/node_modules/.bin/vite --host 127.0.0.1" | tail -n 1 || true)
simulator_pid=$(pgrep -f "$app/node_modules/@evenrealities/sim-linux-x64/bin/evenhub-simulator" | tail -n 1 || true)
kill -0 "$vite_pid" 2>/dev/null
kill -0 "$simulator_pid" 2>/dev/null
printf '%s\n' "$vite_pid" > "$runtime/vite.pid"
printf '%s\n' "$simulator_pid" > "$runtime/simulator.pid"
curl -fsS --max-time 3 http://127.0.0.1:8792/api/ping >/dev/null
echo "Herden HUD simulator is open on Agneta."
REMOTE
    ;;
  *)
    echo "usage: $0 {open|refresh|status|screenshot|input|stop}" >&2
    exit 2
    ;;
esac
