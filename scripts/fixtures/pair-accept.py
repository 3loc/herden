#!/usr/bin/env python3
"""Test double for the Host's restricted `herden pair accept` command.

The runtime has its own Rust coverage. This fixture lets the iOS real-SSH suite
exercise the wire ceremony without building a second macOS executable inside
the Xcode job.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import time


def reply_error(code: str, detail: str) -> None:
    print(f"HERDR-ENROLL:ERR:{code}")
    print(detail, file=sys.stderr)
    raise SystemExit(1)


def remove_bootstrap(keys_path: Path, pairing_id: str) -> list[str]:
    lines = keys_path.read_text().splitlines() if keys_path.exists() else []
    marker = f" herden-pairing:{pairing_id}:exp:"
    kept = [line for line in lines if marker not in line]
    keys_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = keys_path.with_suffix(".pairing-fixture.tmp")
    temporary.write_text("".join(f"{line}\n" for line in kept))
    os.chmod(temporary, 0o600)
    os.replace(temporary, keys_path)
    return kept


def parse_device_key(line: str) -> tuple[str, bytes, str]:
    fields = line.strip().split()
    if len(fields) < 2 or fields[0] != "ssh-ed25519":
        raise ValueError("expected an ssh-ed25519 public key")
    try:
        blob = base64.b64decode(fields[1], validate=True)
        algorithm_length = struct.unpack(">I", blob[:4])[0]
        offset = 4 + algorithm_length
        algorithm = blob[4:offset]
        key_length = struct.unpack(">I", blob[offset : offset + 4])[0]
        key = blob[offset + 4 :]
    except (ValueError, struct.error) as error:
        raise ValueError("malformed OpenSSH key") from error
    if algorithm != b"ssh-ed25519" or key_length != 32 or len(key) != 32:
        raise ValueError("malformed Ed25519 key")
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(blob).digest()).decode().rstrip("=")
    return f"ssh-ed25519 {fields[1]}", blob, fingerprint


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--pairing-id", required=True)
    arguments = parser.parse_args()

    home = Path(os.environ["HOME"])
    state_dir = Path(arguments.state_dir)
    pending_path = state_dir / "pending" / f"{arguments.pairing_id}.json"
    keys_path = home / ".ssh" / "authorized_keys"
    try:
        pending = json.loads(pending_path.read_text())
    except (OSError, ValueError):
        remove_bootstrap(keys_path, arguments.pairing_id)
        reply_error("unknown_pairing", "no pending Pairing ceremony")

    if int(time.time()) > int(pending["expiresAt"]):
        remove_bootstrap(keys_path, arguments.pairing_id)
        pending_path.unlink(missing_ok=True)
        reply_error("expired", "Pairing ceremony expired")

    submission = sys.stdin.buffer.readline(4097)
    if not submission.strip():
        reply_error("no_input", "expected a Device Key public line")
    if len(submission) > 4096:
        reply_error("invalid_key", "Device Key line is too long")
    try:
        device_line, device_blob, fingerprint = parse_device_key(submission.decode())
    except (UnicodeDecodeError, ValueError) as error:
        reply_error("invalid_key", str(error))

    kept = remove_bootstrap(keys_path, arguments.pairing_id)
    pending_path.unlink(missing_ok=True)
    existing_blobs = set()
    for line in kept:
        try:
            existing_blobs.add(parse_device_key(line)[1])
        except ValueError:
            pass
    if device_blob not in existing_blobs:
        with keys_path.open("a") as authorized_keys:
            authorized_keys.write(device_line + "\n")

    enrolled_dir = state_dir / "enrolled"
    enrolled_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    record = {
        "pairingId": arguments.pairing_id,
        "expiresAt": pending["expiresAt"],
        "fingerprint": fingerprint,
        "line": device_line,
    }
    (enrolled_dir / f"{arguments.pairing_id}.json").write_text(json.dumps(record))
    print(f"HERDR-ENROLL:OK:{fingerprint}")


if __name__ == "__main__":
    main()
