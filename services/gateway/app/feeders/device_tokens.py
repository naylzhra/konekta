"""API tokens for IoT devices.

Tokens are 256-bit random values, so a plain SHA-256 is enough to store them
safely. bcrypt (app/auth/passwords.py) is for low-entropy passwords and would
cost ~100+ ms of CPU on every 1 Hz device report.
"""
import hashlib
import hmac
import secrets


def generate_token() -> str:
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def verify_token(token: str, token_hash: str) -> bool:
    return hmac.compare_digest(hash_token(token), token_hash)
