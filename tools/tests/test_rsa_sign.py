#!/usr/bin/env python3
"""RSA-PSS signing (std/rsa.nu over std/rsa_mont.nu) against OpenSSL.

For each key size, tools/rsa_sign_gate signs a set of digests through the
CRT blob and through the plain private exponent. PSS with a fixed salt is
deterministic, so the two must agree byte for byte; OpenSSL must verify
the signature; and std/rsa.nu's own verify must accept it.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SIZES = (1024, 2048, 3072, 4096)


class RsaSignTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get('RSA_SIGN_GATE', ROOT/'build/rsa_sign_gate')).resolve()
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-rsa-sign-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.dir = Path(cls.temp.name)

    def key(self, bits, form):
        path = self.dir/f'rsa{bits}-{form}.pem'
        if not path.exists():
            src = self.dir/f'rsa{bits}.pem'
            if not src.exists():
                subprocess.run(['openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt',
                                f'rsa_keygen_bits:{bits}', '-out', str(src)],
                               check=True, capture_output=True)
            if form == 'pkcs8':
                path = src
            else:  # PKCS#1 "RSA PRIVATE KEY"
                subprocess.run(['openssl', 'rsa', '-traditional', '-in', str(src), '-out', str(path)],
                               check=True, capture_output=True)
        return path

    def openssl_verify(self, key, digest, sig):
        pub = key.with_suffix('.pub')
        if not pub.exists():
            subprocess.run(['openssl', 'pkey', '-in', str(key), '-pubout', '-out', str(pub)],
                           check=True, capture_output=True)
        d, s = self.dir/'digest.bin', self.dir/'sig.bin'
        d.write_bytes(digest)
        s.write_bytes(sig)
        r = subprocess.run(['openssl', 'pkeyutl', '-verify', '-pubin', '-inkey', str(pub),
                            '-in', str(d), '-sigfile', str(s),
                            '-pkeyopt', 'digest:sha256', '-pkeyopt', 'rsa_padding_mode:pss',
                            '-pkeyopt', 'rsa_pss_saltlen:32'], capture_output=True, text=True)
        return r.returncode == 0

    def test_sign(self):
        for bits in SIZES:
            for form in ('pkcs8', 'pkcs1'):
                key = self.key(bits, form)
                for i in range(3):
                    digest = hashlib.sha256(f'message {bits} {i}'.encode()).digest()
                    salt = hashlib.sha256(f'salt {i}'.encode()).digest()
                    with self.subTest(bits=bits, form=form, i=i):
                        r = subprocess.run([str(self.binary), str(key), digest.hex(), salt.hex()],
                                           capture_output=True, text=True, timeout=120)
                        self.assertEqual(r.returncode, 0, r.stderr)
                        crt, plain, own = r.stdout.split('\n')[:3]
                        self.assertEqual(len(crt), bits // 4, 'signature is k bytes')
                        self.assertEqual(crt, plain, 'CRT and plain-d signatures differ')
                        self.assertEqual(own, 'verify ok')
                        self.assertTrue(self.openssl_verify(key, digest, bytes.fromhex(crt)),
                                        'OpenSSL rejects the signature')


if __name__ == '__main__':
    unittest.main()
