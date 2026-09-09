#!/bin/sh
# installed by Herden
# managed by Herden; reinstalling or updating the integration overwrites this file.
# add custom hooks beside this file instead of editing it.
# HERDR_INTEGRATION_ID=codex
# HERDR_INTEGRATION_VERSION=9

set -eu

action="${1:-}"
session_arg="${2:-}"
hook_input_file="$(mktemp "${TMPDIR:-/tmp}/herdr-codex-hook.XXXXXX")" || exit 0
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

case "$action" in
  session) ;;
  title) ;;
  *) exit 0 ;;
esac

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

HERDR_ACTION="$action" HERDR_SESSION_ARG="$session_arg" HERDR_HOOK_SCRIPT="$0" HERDR_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY'
import glob
import json
import os
import random
import sqlite3
import socket
import subprocess
import time

source = "herden:codex"
action = os.environ.get("HERDR_ACTION", "")
pane_id = os.environ.get("HERDR_PANE_ID")
socket_path = os.environ.get("HERDR_SOCKET_PATH")
hook_input_file = os.environ.get("HERDR_HOOK_INPUT_FILE")

if not pane_id or not socket_path:
    raise SystemExit(0)

hook_input = {}
if hook_input_file:
    try:
        with open(hook_input_file, encoding="utf-8") as handle:
            content = handle.read()
        if content.strip():
            hook_input = json.loads(content)
    except Exception:
        hook_input = {}

hook_event_name = str(hook_input.get("hook_event_name") or "")
if action == "title":
    session_id = os.environ.get("HERDR_SESSION_ARG") or ""
    if not session_id:
        raise SystemExit(0)

    # SessionStart runs before Codex has generated its short thread name. One
    # lightweight watcher follows that row and reports changes through the
    # existing metadata API. A per-thread flock prevents reload/resume hooks
    # from accumulating duplicate watchers.
    import fcntl
    import hashlib
    lock_name = hashlib.sha256(session_id.encode()).hexdigest()[:24]
    codex_home = os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")
    lock_path = os.path.join(codex_home, f".herden-title-{lock_name}.lock")
    try:
        lock_handle = open(lock_path, "w", encoding="utf-8")
        fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except Exception:
        raise SystemExit(0)

    def state_databases():
        def version(path):
            stem = os.path.basename(path).removeprefix("state_").removesuffix(".sqlite")
            try:
                return int(stem)
            except ValueError:
                return -1
        return sorted(glob.glob(os.path.join(codex_home, "state_*.sqlite")), key=version, reverse=True)

    def thread_name():
        for database in state_databases():
            try:
                connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=0.25)
                try:
                    row = connection.execute(
                        "SELECT name FROM threads WHERE id = ?", (session_id,)
                    ).fetchone()
                finally:
                    connection.close()
                if row is not None:
                    value = row[0]
                    return value.strip() if isinstance(value, str) and value.strip() else None
            except Exception:
                continue
        return None

    def report_title(title):
        request = {
            "id": f"{source}:title:{int(time.time() * 1000)}:{random.randrange(1_000_000):06d}",
            "method": "pane.report_metadata",
            "params": {
                "pane_id": pane_id,
                "source": source,
                "agent": "codex",
                "applies_to_source": source,
                "seq": time.time_ns(),
            },
        }
        if title:
            request["params"]["title"] = title
        else:
            request["params"]["clear_title"] = True
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.settimeout(0.75)
            client.connect(socket_path)
            client.sendall((json.dumps(request) + "\n").encode())
            response = client.recv(4096)
            client.close()
            if response:
                decoded = json.loads(response.splitlines()[0])
                return decoded.get("error", {}).get("code") != "pane_not_found"
            return True
        except Exception:
            return os.path.exists(socket_path)

    previous = object()
    last_reported_at = 0.0
    while True:
        current = thread_name()
        now = time.monotonic()
        if current != previous or now - last_reported_at >= 30:
            if not report_title(current):
                break
            previous = current
            last_reported_at = now
        elif not os.path.exists(socket_path):
            break
        time.sleep(2)
    raise SystemExit(0)

if hook_event_name and hook_event_name != "SessionStart":
    raise SystemExit(0)

request_id = f"{source}:{int(time.time() * 1000)}:{random.randrange(1_000_000):06d}"
report_seq = time.time_ns()
session_id = hook_input.get("session_id")
agent_session_id = session_id if isinstance(session_id, str) and session_id else None
transcript_path = hook_input.get("transcript_path")
if not isinstance(transcript_path, str) or not transcript_path.strip():
    raise SystemExit(0)
inherited_session_id = os.environ.get("CODEX_THREAD_ID")
if inherited_session_id and inherited_session_id != agent_session_id:
    raise SystemExit(0)
session_start_source = hook_input.get("source") if hook_event_name == "SessionStart" else None
if not isinstance(session_start_source, str) or not session_start_source:
    session_start_source = None
if agent_session_id:
    params = {
        "pane_id": pane_id,
        "source": source,
        "agent": "codex",
        "seq": report_seq,
        "agent_session_id": agent_session_id,
    }
    if session_start_source:
        params["session_start_source"] = session_start_source
    request = {
        "id": request_id,
        "method": "pane.report_agent_session",
        "params": params,
    }
else:
    raise SystemExit(0)

try:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    client.connect(socket_path)
    client.sendall((json.dumps(request) + "\n").encode())
    try:
        client.recv(4096)
    except Exception:
        pass
    client.close()
except Exception:
    pass

if action == "session" and agent_session_id:
    try:
        subprocess.Popen(
            [os.environ["HERDR_HOOK_SCRIPT"], "title", agent_session_id],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass
PY
