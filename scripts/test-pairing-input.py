#!/usr/bin/env python3
"""Exercise pairing cancellation in a Linux PTY, with an isolated HOME.

Usage: python3 scripts/test-pairing-input.py /path/to/herden
Requires the Host's readable SSH public host key, as `herden pair` does.
"""

import argparse
import json
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time


def wait_until(check, message, timeout=10):
    deadline = time.monotonic() + timeout
    while not check():
        if time.monotonic() >= deadline:
            raise AssertionError(message)
        time.sleep(0.02)


def check_cancel(binary, key, expected_status, qr_only, redirected=False):
    with tempfile.TemporaryDirectory(prefix="herden-pair-input-") as directory:
        root = Path(directory)
        keys = root / ".ssh/authorized_keys"
        keys.parent.mkdir(mode=0o700)
        original_keys = "# Existing authorized keys must survive cancellation.\n"
        keys.write_text(original_keys)
        state = root / "pairing"
        env = dict(os.environ, HOME=str(root), USER="pairing-test",
                   HERDEN_PAIRING_STATE_DIR=str(state))
        master, slave = pty.openpty()
        original_terminal = termios.tcgetattr(slave)

        def controlling_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        argv = [str(binary), "pair", "--address", "127.0.0.1"]
        if qr_only:
            argv.append("--qr-only")
        process = subprocess.Popen(
            argv, env=env,
            stdin=subprocess.DEVNULL if redirected else slave,
            stdout=subprocess.PIPE if redirected else slave,
            stderr=subprocess.STDOUT if redirected else slave,
            preexec_fn=None if redirected else controlling_terminal,
        )
        try:
            output_fd = process.stdout.fileno() if redirected else master
            output = bytearray()
            marker = b"This code expires" if redirected else b"Press q, Esc or Ctrl+C"

            def ready():
                assert process.poll() is None, "pairing exited before displaying the QR code"
                if select.select([output_fd], [], [], 0.05)[0]:
                    output.extend(os.read(output_fd, 65536))
                return marker in output

            wait_until(ready, "pairing did not display its QR code")
            assert "herden-pairing:" in keys.read_text(), "bootstrap key was not installed"
            assert list((state / "pending").glob("*.json")), "pairing state was not created"
            if not redirected:
                wait_until(lambda: not termios.tcgetattr(slave)[3] & termios.ICANON,
                           "pairing did not enable immediate key input")
                os.write(master, b"x")
                time.sleep(0.15)
                assert process.poll() is None, "ordinary input closed pairing"
            if key is None:
                process.send_signal(signal.SIGINT)
            else:
                os.write(master, key)
            assert process.wait(timeout=5) == expected_status, "unexpected cancellation exit code"
            assert keys.read_text() == original_keys, "temporary bootstrap access was not removed"
            assert not list(state.rglob("*.json")), "pending pairing state was not removed"
            assert termios.tcgetattr(slave) == original_terminal, "terminal settings were not restored"
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            if process.stdout:
                process.stdout.close()
            os.close(master)
            os.close(slave)



def check_popup_client(binary, previous_binary=None):
    """Exercise Ctrl-B i and the close keys through the actual TUI client."""
    with tempfile.TemporaryDirectory(prefix="herden-qr-popup-") as directory:
        root = Path(directory)
        config = root / "config/herden"
        config.mkdir(parents=True)
        (config / "config.toml").write_text("onboarding = false\n")
        state = root / "pairing"
        keys = root / ".ssh/authorized_keys"
        keys.parent.mkdir(mode=0o700)
        keys.write_text("# Preserve this line.\n")
        api_socket = root / "api.sock"
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("HERDR_")}
        env.update(HOME=str(root), USER="pairing-test", SHELL="/bin/sh",
                   TERM="xterm-256color", XDG_CONFIG_HOME=str(root / "config"),
                   XDG_STATE_HOME=str(root / "state"), XDG_RUNTIME_DIR=str(root),
                   HERDR_CONFIG_PATH=str(config / "config.toml"),
                   HERDR_SOCKET_PATH=str(api_socket),
                   HERDR_CLIENT_SOCKET_PATH=str(root / "client.sock"),
                   HERDEN_PAIRING_STATE_DIR=str(state), HERDR_DISABLE_SOUND="1")

        def rpc(method, params=None):
            with socket.socket(socket.AF_UNIX) as connection:
                connection.settimeout(5)
                connection.connect(str(api_socket))
                connection.sendall((json.dumps({"id": "test", "method": method,
                                               "params": params or {}}) + "\n").encode())
                return json.loads(connection.makefile("rb").readline())

        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 120, 0, 0))
        client = None
        server_binary = binary
        if previous_binary:
            server_binary = root / "herden"
            shutil.copy2(previous_binary, server_binary)
        with (root / "server.log").open("w+") as log:
            server = subprocess.Popen([str(server_binary), "server"], env=env,
                                      stdout=log, stderr=log)
            try:
                wait_until(api_socket.exists, "temporary Host did not start")
                assert "result" in rpc("ping")
                assert "result" in rpc("workspace.create", {"cwd": str(root)})
                if previous_binary:
                    replacement = root / "herden.next"
                    shutil.copy2(binary, replacement)
                    replacement.replace(server_binary)

                def controlling_terminal():
                    os.setsid()
                    fcntl.ioctl(0, termios.TIOCSCTTY, 0)

                client = subprocess.Popen([str(binary), "client"], env=env,
                                          stdin=slave, stdout=slave, stderr=slave,
                                          preexec_fn=controlling_terminal)

                terminal_output = bytearray()

                def pump():
                    if select.select([master], [], [], 0.05)[0]:
                        terminal_output.extend(os.read(master, 65536))
                    assert client.poll() is None, "TUI exited unexpectedly"

                # Let the client finish its initial handshake and frame.
                until = time.monotonic() + 1
                while time.monotonic() < until:
                    pump()
                assert b"[herden]" in terminal_output, "persistent Herden sidebar identity is missing"
                print("PASS real TUI: persistent [herden] identity is visible")
                for name, key in (("q", b"q"), ("Escape", b"\x1b"), ("Ctrl+C", b"\x03")):
                    os.write(master, b"\x02i")

                    def popup_ready():
                        pump()
                        return bool(list((state / "pending").glob("*.json")))

                    wait_until(popup_ready, "Ctrl-B i did not open the pairing popup")
                    # Wait for its input loop, not merely the bootstrap-key write.
                    until = time.monotonic() + 0.3
                    while time.monotonic() < until:
                        pump()
                    os.write(master, key)

                    def popup_cleaned():
                        pump()
                        return not list((state / "pending").glob("*.json"))

                    wait_until(popup_cleaned, f"{name} did not cancel the real popup", timeout=5)
                    until = time.monotonic() + 0.3
                    while time.monotonic() < until:
                        pump()
                    response = rpc("popup.close")
                    assert response.get("error", {}).get("code") == "popup_not_open", response
                    assert keys.read_text() == "# Preserve this line.\n"
                    context = "upgraded running Host" if previous_binary else "real TUI"
                    print(f"PASS {context} Ctrl-B i / {name}: popup closed, client alive, keys cleaned")
            finally:
                if client is not None:
                    client.terminate()
                    client.wait(timeout=5)
                try:
                    rpc("server.stop")
                except (OSError, ValueError):
                    pass
                if server.poll() is None:
                    try:
                        server.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        server.kill()
                        server.wait()
                os.close(master)
                os.close(slave)


def main():
    # Apple's system Python can hang between fork and exec with preexec_fn.
    # Test macOS with a native SSH PTY instead of this Linux harness.
    if sys.platform != "linux":
        raise SystemExit("Run this PTY harness on Linux; verify macOS keys in a native SSH terminal.")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--previous-binary", type=Path,
                        help="also verify popup launching after replacing a running Host's executable")
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    for qr_only in (False, True):
        for name, key, status in (("q", b"q", 0), ("Escape", b"\x1b", 0),
                                  ("Ctrl+C", b"\x03", 130), ("SIGINT", None, 130)):
            check_cancel(binary, key, status, qr_only)
            print(f"PASS {'popup' if qr_only else 'CLI'} {name}: closed, keys cleaned, terminal restored")
    check_cancel(binary, None, 130, qr_only=True, redirected=True)
    print("PASS redirected SIGINT: closed and keys cleaned")
    check_popup_client(binary)
    if args.previous_binary:
        check_popup_client(binary, args.previous_binary.resolve(strict=True))


if __name__ == "__main__":
    main()
