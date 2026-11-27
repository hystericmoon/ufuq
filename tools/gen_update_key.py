#!/usr/bin/env python3
"""Generate the Ed25519 keypair that signs Ufuq update installers.

Prints two base64 values:
  private key (raw 32-byte seed)  -> GitHub secret   UFUQ_UPDATE_PRIVATE_KEY
  public key  (raw 32 bytes)      -> GitHub variable UFUQ_UPDATE_PUBLIC_KEY

Needs `pip install cryptography`. Run once, store the private key only in the secret
(and a password manager), and never commit it. Losing it means shipping a new public key
in a manually installed build, because installed apps trust only the key they were built with.
"""
import base64

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

key = Ed25519PrivateKey.generate()
private_raw = key.private_bytes(
    serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption()
)
public_raw = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)

print("UFUQ_UPDATE_PRIVATE_KEY (secret, keep private):")
print(base64.b64encode(private_raw).decode())
print()
print("UFUQ_UPDATE_PUBLIC_KEY (repository variable):")
print(base64.b64encode(public_raw).decode())
