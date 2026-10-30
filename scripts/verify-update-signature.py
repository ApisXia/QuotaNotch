#!/usr/bin/env python3
"""Verify a Sparkle EdDSA signature against the public key from Info.plist."""
import base64
import sys

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

archive, signature, public_key = sys.argv[1:4]
key = Ed25519PublicKey.from_public_bytes(base64.b64decode(public_key))
with open(archive, "rb") as stream:
    key.verify(base64.b64decode(signature), stream.read())
print("Update signature matches the app's public key.")
