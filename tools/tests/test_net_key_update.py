#!/usr/bin/env python3
"""TLS1.3 KeyUpdate in both directions against the OpenSSL implementation."""
import os
from pathlib import Path
import select
import socket
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class KeyUpdateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get('NET_KEY_UPDATE', ROOT/'build/net_key_update')).resolve()
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-key-update-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        cls.cert, cls.key = cls.directory/'cert.pem', cls.directory/'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt',
                        'ec_paramgen_curve:prime256v1', '-keyout', str(cls.key),
                        '-out', str(cls.cert), '-nodes', '-days', '1',
                        '-subj', '/CN=localhost'], check=True, capture_output=True)
        cls.peer = cls.directory/'openssl-peer'
        subprocess.run(['cc', '-O2', str(ROOT/'tools/tests/net_key_update_peer.c'),
                        '-o', str(cls.peer), '-lssl', '-lcrypto'], check=True, capture_output=True)

    def exchange(self, role, mode, request, cipher):
        errors = []
        sockets = []
        processes = []
        threads = []
        stop = threading.Event()
        try:
            if role == 0:
                listener = socket.socket()
                sockets.append(listener)
                listener.bind(('127.0.0.1', 0))
                listener.listen()
                listener.settimeout(7)
                port = listener.getsockname()[1]
            else:
                port = 0
            nurl = subprocess.Popen([str(self.binary), str(port), str(role), str(mode),
                                     str(self.cert), str(self.key)], stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE)
            processes.append(nurl)
            if role == 0:
                connection, _ = listener.accept()
            else:
                self.assertTrue(select.select([nurl.stdout], [], [], 7)[0], 'listener did not start')
                address = nurl.stdout.readline().decode().strip()
                if not address:
                    self.fail(nurl.stderr.read())
                connection = socket.create_connection(('127.0.0.1', int(address.rsplit(':', 1)[1])), 7)
            sockets.append(connection)
            left, right = socket.socketpair()
            sockets.extend([left, right])
            connection.settimeout(7)
            left.settimeout(7)
            peer = subprocess.Popen([str(self.peer), str(right.fileno()), str(1-role), str(request),
                                     str(self.cert), str(self.key), cipher], pass_fds=(right.fileno(),),
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            processes.append(peer)
            right.close()

            def transfer(source, destination, fragment):
                try:
                    data = bytearray()
                    while not stop.is_set():
                        chunk = source.recv(65536)
                        if not chunk:
                            break
                        if not fragment:
                            destination.sendall(chunk)
                            continue
                        data.extend(chunk)
                        while len(data) >= 5:
                            length = 5 + int.from_bytes(data[3:5], 'big')
                            if len(data) < length:
                                break
                            record = bytes(data[:length])
                            del data[:length]
                            # Every OpenSSL record, including each KeyUpdate, arrives
                            # with an incomplete header first. This also covers tickets.
                            destination.sendall(record[:3])
                            time.sleep(0.001)
                            destination.sendall(record[3:])
                except (BrokenPipeError, ConnectionResetError):
                    pass
                except OSError as error:
                    if not stop.is_set():
                        errors.append(error)
                finally:
                    try:
                        destination.shutdown(socket.SHUT_WR)
                    except OSError:
                        pass

            for source, destination, fragment in ((left, connection, True), (connection, left, False)):
                thread = threading.Thread(target=transfer, args=(source, destination, fragment), daemon=True)
                threads.append(thread)
                thread.start()
            peer_out, peer_err = peer.communicate(timeout=10)
            nurl_out, nurl_err = nurl.communicate(timeout=10)
            self.assertEqual(peer.returncode, 0, peer_out+peer_err+nurl_err)
            self.assertEqual(nurl.returncode, 0, nurl_out+nurl_err)
            self.assertNotIn(b'Sanitizer', nurl_err)
            self.assertNotIn(b'runtime error:', nurl_err)
            self.assertFalse(errors, errors)
        finally:
            stop.set()
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.communicate()
            for connection in sockets:
                connection.close()
            for thread in threads:
                thread.join(timeout=1)

    def test_multiple_updates_with_fragmented_records(self):
        for role in (0, 1):
            for mode in range(4):
                for request in (0, 1):
                    for cipher in ('TLS_AES_128_GCM_SHA256', 'TLS_CHACHA20_POLY1305_SHA256'):
                        with self.subTest(role=role, mode=mode, request=request, cipher=cipher):
                            self.exchange(role, mode, request, cipher)


if __name__ == '__main__':
    unittest.main(verbosity=2)
