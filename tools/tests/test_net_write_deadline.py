#!/usr/bin/env python3
"""Absolute TCP/TLS send deadline under stalled and progressing peers."""
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WriteDeadlineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get('NET_DEADLINE', ROOT/'build/net_write_deadline')).resolve()
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-write-deadline-')
        cls.addClassCleanup(cls.temp.cleanup)
        cert, key = Path(cls.temp.name)/'cert.pem', Path(cls.temp.name)/'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt',
                        'ec_paramgen_curve:prime256v1', '-keyout', str(key), '-out', str(cert),
                        '-nodes', '-days', '1', '-subj', '/CN=localhost'],
                       check=True, capture_output=True)
        cls.tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        cls.tls.minimum_version = ssl.TLSVersion.TLSv1_3
        cls.tls.load_cert_chain(cert, key)

    def run_peer(self, mode, asynchronous, progressing):
        server = socket.socket()
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8192)
        server.bind(('127.0.0.1', 0))
        server.listen()
        done = threading.Event()
        errors = []
        def peer():
            try:
                with server:
                    conn, _ = server.accept()
                    conn.settimeout(3)
                    if mode >= 4:
                        conn = self.tls.wrap_socket(conn, server_side=True)
                    with conn:
                        until = time.monotonic()+1.0
                        while not done.is_set() and time.monotonic() < until:
                            if progressing:
                                if not conn.recv(2048):
                                    break
                            done.wait(0.01)
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                pass
            except Exception as error:
                errors.append(error)
        thread = threading.Thread(target=peer, daemon=True)
        thread.start()
        try:
            run = subprocess.run([str(self.binary), str(server.getsockname()[1]),
                                  str(mode), str(int(asynchronous))],
                                 capture_output=True, timeout=4)
        finally:
            done.set()
            thread.join(timeout=4)
            server.close()
        self.assertFalse(errors, errors)
        self.assertFalse(thread.is_alive())
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)
        elapsed = int(run.stdout.strip())
        self.assertGreaterEqual(elapsed, 65, run.stdout+run.stderr)
        self.assertLess(elapsed, 600, run.stdout+run.stderr)

    def test_absolute_deadline_survives_short_writes_and_progress(self):
        for mode in range(6):
            for asynchronous in ([False] if mode < 2 else [False, True]):
                for progressing in [False, True]:
                    with self.subTest(mode=mode, asynchronous=asynchronous, progressing=progressing):
                        self.run_peer(mode, asynchronous, progressing)


if __name__ == '__main__':
    unittest.main(verbosity=2)
