"""Deterministic Ed25519 signing for isolated registry tests (never production keys)."""
import base64
from pathlib import Path
import subprocess


def make_key(directory, seed):
    key = Path(directory) / f'fixture-{seed}.der'
    key.write_bytes(bytes.fromhex('302e020100300506032b657004220420') + bytes([seed]) * 32)
    pub = subprocess.run(['openssl', 'pkey', '-inform', 'DER', '-in', str(key),
                          '-pubout', '-outform', 'DER'], capture_output=True, check=True, timeout=10).stdout[-32:]
    keyid = bytes([seed + 9]) * 8
    return key, keyid, base64.b64encode(b'Ed' + keyid + pub).decode()


def sign_file(path, key):
    private, keyid, _ = key
    sig = subprocess.run(['openssl', 'pkeyutl', '-sign', '-rawin', '-keyform', 'DER',
                          '-inkey', str(private), '-in', str(path)],
                         capture_output=True, check=True, timeout=10).stdout
    return b'untrusted comment: isolated fixture\n' + base64.b64encode(b'Ed' + keyid + sig) + b'\n'
