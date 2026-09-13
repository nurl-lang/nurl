#!/usr/bin/env python3
"""A fragmented TLS response must not stall queued outbound TLS records."""
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
PAYLOAD_SIZE = 4 * 1024 * 1024


class DuplexTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get('NET_DUPLEX', ROOT/'build/net_duplex_probe')).resolve()
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-net-duplex-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.cert, cls.key = Path(cls.temp.name)/'cert.pem', Path(cls.temp.name)/'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt',
                        'ec_paramgen_curve:prime256v1', '-keyout', str(cls.key),
                        '-out', str(cls.cert), '-nodes', '-days', '1',
                        '-subj', '/CN=localhost'], check=True, capture_output=True)

    def run_peer(self, version, asynchronous):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = context.maximum_version = version
        context.load_cert_chain(self.cert, self.key)
        listener = socket.socket()
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8192)
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        port = listener.getsockname()[1]
        errors = []
        completed = []

        def peer():
            try:
                with listener:
                    conn, _ = listener.accept()
                    with conn:
                        conn.settimeout(5)
                        incoming, outgoing = ssl.MemoryBIO(), ssl.MemoryBIO()
                        tls = context.wrap_bio(incoming, outgoing, server_side=True)

                        def flush():
                            while outgoing.pending:
                                conn.sendall(outgoing.read())

                        def receive():
                            wire = conn.recv(65536)
                            if not wire:
                                raise EOFError('peer closed before the complete request')
                            incoming.write(wire)

                        while True:
                            try:
                                tls.do_handshake()
                                flush()
                                break
                            except ssl.SSLWantReadError:
                                flush()
                                receive()

                        tls.write(b'hello partial')
                        response = outgoing.read()
                        self.assertGreater(len(response), 5)
                        # Withhold the rest until the client's complete request arrives.
                        # A blocking TLS read of this partial header would deadlock.
                        conn.sendall(response[:3])
                        count = 0
                        while count < PAYLOAD_SIZE:
                            try:
                                chunk = tls.read(65536)
                                self.assertTrue(chunk)
                                self.assertEqual(chunk, b'A' * len(chunk))
                                count += len(chunk)
                            except ssl.SSLWantReadError:
                                flush()
                                receive()
                        self.assertEqual(count, PAYLOAD_SIZE)
                        conn.sendall(response[3:])
                        completed.append(True)
                        # Let the client consume the response and send close_notify.
                        try:
                            conn.recv(65536)
                        except ConnectionResetError:
                            pass
            except Exception as error:
                errors.append(error)

        thread = threading.Thread(target=peer, daemon=True)
        thread.start()
        try:
            run = subprocess.run([str(self.binary), str(port), str(int(asynchronous))],
                                 capture_output=True, timeout=7)
        finally:
            thread.join(timeout=6)
            listener.close()
        self.assertFalse(thread.is_alive())
        self.assertFalse(errors, errors)
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)
        self.assertEqual(completed, [True])

    def test_fragmented_response_during_large_send(self):
        for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
            for asynchronous in (False, True):
                with self.subTest(version=version.name, asynchronous=asynchronous):
                    self.run_peer(version, asynchronous)


if __name__ == '__main__':
    unittest.main(verbosity=2)
