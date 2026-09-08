#!/usr/bin/env python3
"""Send one App Store Connect API request with credentials injected via env."""

import argparse
import base64
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request


def encode(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=")


def make_token():
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils

    key_id = os.environ["APP_STORE_CONNECT_KEY_ID"]
    issuer_id = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
    encoded_key = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_P8_BASE64")
    key_path = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_PATH")
    if bool(encoded_key) == bool(key_path):
        raise ValueError("Set exactly one private-key environment variable")
    pem = base64.b64decode(encoded_key, validate=True) if encoded_key else Path(key_path).read_bytes()
    key = serialization.load_pem_private_key(pem, password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey) or key.curve.name != "secp256r1":
        raise ValueError("App Store Connect requires a P-256 signing key")
    now = int(time.time())
    header = encode(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = encode(json.dumps({"iss": issuer_id, "iat": now, "exp": now + 600,
                                 "aud": "appstoreconnect-v1"}).encode())
    body = header + b"." + payload
    r, s = utils.decode_dss_signature(key.sign(body, ec.ECDSA(hashes.SHA256())))
    return (body + b"." + encode(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()


def redact(value):
    if isinstance(value, dict):
        return {k: "[REDACTED]" if any(word in k.lower() for word in ("password", "privatekey", "secret"))
                and v is not None else redact(v) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward the bearer token to a different location.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="Quoted /v1/... API path, including any query")
    parser.add_argument("--method", choices=("GET", "POST", "PATCH", "DELETE"), default="GET")
    parser.add_argument("--body-file", type=Path, help="JSON request body; use a temporary file")
    args = parser.parse_args()
    if not args.path.startswith(("/v1/", "/v2/")) or "#" in args.path:
        parser.error("Use a relative /v1/ or /v2/ API path")
    if args.method == "GET" and args.body_file:
        parser.error("GET requests must not include a body")
    try:
        body = json.dumps(json.loads(args.body_file.read_text())).encode() if args.body_file else None
        token = make_token()
    except (KeyError, ValueError, OSError, ImportError) as error:
        print(f"Configuration error ({type(error).__name__}); check credential variables, key format, JSON, and Python cryptography.", file=sys.stderr)
        return 2
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + args.path,
        data=body, method=args.method,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=40) as response:
            raw = response.read()
            result = json.loads(raw) if raw else {"status": response.status}
    except urllib.error.HTTPError as error:
        try:
            details = redact(json.loads(error.read()))
        except ValueError:
            details = "Non-JSON error response"
        print(json.dumps({"status": error.code, "error": details}, indent=2), file=sys.stderr)
        return 1
    except (OSError, ValueError) as error:
        print(f"Request failed ({type(error).__name__}). Read remote state before retrying a mutation.", file=sys.stderr)
        return 1
    print(json.dumps(redact(result), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
