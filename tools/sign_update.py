#!/usr/bin/env python3
"""Sign an installer with Ed25519: writes <file>.sig (base64 of the raw 64-byte signature).

Usage: sign_update.py <installer> ; the base64 raw 32-byte private key comes from the
UFUQ_UPDATE_PRIVATE_KEY environment variable. The app verifies the signature over the installer bytes.
"""
import base64
import os
import sys

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

if len(sys.argv) != 2:
    sys.exit("usage: sign_update.py <installer>")
secret = os.environ.get("UFUQ_UPDATE_PRIVATE_KEY", "").strip()
if not secret:
    sys.exit("UFUQ_UPDATE_PRIVATE_KEY is not set")
key = Ed25519PrivateKey.from_private_bytes(base64.b64decode(secret))
with open(sys.argv[1], "rb") as f:
    signature = key.sign(f.read())
with open(sys.argv[1] + ".sig", "w") as f:
    f.write(base64.b64encode(signature).decode() + "\n")
print(f"wrote {sys.argv[1]}.sig")
