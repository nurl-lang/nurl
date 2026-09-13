#!/usr/bin/env python3
"""gRPC interoperability against the official C-core Python runtime.

python -m pip install -r packages/gRPC/tests/requirements.txt
python tools/tests/test_grpc.py
NURL_SAN=1 uses the same cases with ASan/UBSan and leak detection.
"""
from concurrent import futures
from contextlib import contextmanager
import os
from pathlib import Path
import queue
import select
import socket
import struct
import subprocess
import tempfile
import threading
import time
import unittest

import grpc
import h2.config
import h2.connection
import h2.events

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "packages/gRPC"


class GrpcTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="nurl-grpc-")
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.directory = Path(cls.tmp.name)
        cls.env = {**os.environ, "ASAN_OPTIONS": "detect_leaks=1:halt_on_error=1",
                   "UBSAN_OPTIONS": "halt_on_error=1", "LSAN_OPTIONS": "use_stacks=0"}
        cls.bins = {}
        for name in ("wire_test", "client", "server"):
            exe = cls.directory / name
            source = PACKAGE / "tests" / ("wire_test.nu" if name == "wire_test" else f"fixtures/{name}.nu")
            built = subprocess.run([str(ROOT / "nurl.sh"),
                                    str(source), str(exe)],
                                   cwd=ROOT, env=cls.env, text=True, capture_output=True, timeout=180)
            if built.returncode or "warning:" in built.stderr:
                raise AssertionError(built.stdout + built.stderr)
            cls.bins[name] = exe
        cls.cert = cls.directory / "cert.pem"
        cls.key = cls.directory / "key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt",
                        "ec_paramgen_curve:P-256", "-nodes", "-days", "1", "-subj",
                        "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
                        "-addext", "basicConstraints=critical,CA:TRUE",
                        "-keyout", str(cls.key), "-out", str(cls.cert)],
                       check=True, capture_output=True, timeout=10)

    @contextmanager
    def nurl_server(self, compression="identity", tls=False):
        args = [str(self.bins["server"]), compression]
        if tls:
            args += [str(self.cert), str(self.key)]
        process = subprocess.Popen(args, cwd=ROOT, env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            ready, _, _ = select.select([process.stdout], [], [], 15)
            if not ready:
                raise AssertionError("server did not report a bound address")
            address = process.stdout.readline().strip()
            if not address:
                raise AssertionError(process.stderr.read())
            yield address
            stdout, stderr = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, stdout + stderr)
            self.assertEqual(stderr, "")
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def channel(self, address, tls=False):
        if tls:
            return grpc.secure_channel(address, grpc.ssl_channel_credentials(self.cert.read_bytes()))
        return grpc.insecure_channel(address)

    @contextmanager
    def oracle_server(self, tls=False):
        def initial(context):
            values = [(key, value) for key, value in context.invocation_metadata()
                      if key in ("trace-bin", "x-repeat")]
            context.send_initial_metadata(values)
            context.set_trailing_metadata((("finished", "yes"),))

        def unary(request, context):
            initial(context)
            return request

        def server_stream(request, context):
            initial(context)
            yield from (request, request, request)

        def client_stream(requests, context):
            initial(context)
            return b"".join(requests)

        def bidi(requests, context):
            initial(context)
            yield from requests

        def error(request, context):
            context.set_trailing_metadata((("grpc-status-details-bin", b"\x08\x03"),))
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "bad % ä")

        def slow(request, context):
            while context.is_active():
                time.sleep(.01)
            return b""

        server = grpc.server(futures.ThreadPoolExecutor(max_workers=8))
        server.add_generic_rpc_handlers((grpc.method_handlers_generic_handler("test.Echo", {
            "Unary": grpc.unary_unary_rpc_method_handler(unary),
            "ServerStream": grpc.unary_stream_rpc_method_handler(server_stream),
            "ClientStream": grpc.stream_unary_rpc_method_handler(client_stream),
            "Bidi": grpc.stream_stream_rpc_method_handler(bidi),
            "Error": grpc.unary_unary_rpc_method_handler(error),
            "Slow": grpc.unary_unary_rpc_method_handler(slow),
        }),))
        if tls:
            credentials = grpc.ssl_server_credentials(((self.key.read_bytes(), self.cert.read_bytes()),))
            port = server.add_secure_port("127.0.0.1:0", credentials)
        else:
            port = server.add_insecure_port("127.0.0.1:0")
        self.assertGreater(port, 0)
        server.start()
        try:
            yield port
        finally:
            server.stop(0).wait(10)

    def client(self, port, method="Unary", mode="unary", compression="identity",
               tls=False, status=0, size=8193):
        result = subprocess.run([str(self.bins["client"]), str(port), f"/test.Echo/{method}",
                                 mode, compression, "tls" if tls else "h2c", str(status), str(size)],
                                cwd=ROOT, env={**self.env, "SSL_CERT_FILE": str(self.cert)},
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")

    def test_wire(self):
        result = subprocess.run([str(self.bins["wire_test"])], env=self.env,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")

    def test_nurl_client_all_call_shapes(self):
        with self.oracle_server() as port:
            for method, mode in (("Unary", "unary"), ("ServerStream", "server-stream"),
                                 ("ClientStream", "client-stream"), ("Bidi", "bidi")):
                with self.subTest(method=method):
                    self.client(port, method, mode)

    def test_nurl_client_compression_empty_and_flow_control(self):
        with self.oracle_server() as port:
            for compression in ("identity", "gzip"):
                for size in (0, 1, 262145):
                    with self.subTest(compression=compression, size=size):
                        self.client(port, compression=compression, size=size)

    def test_nurl_client_status_deadline_tls(self):
        with self.oracle_server(tls=True) as port:
            self.client(port, tls=True)
            self.client(port, "Error", status=3, tls=True)
            self.client(port, "Missing", status=12, tls=True)
            self.client(port, "Slow", status=4, tls=True)

    def test_nurl_client_cancel_reuse_and_multiplex(self):
        with self.oracle_server(tls=True) as port:
            self.client(port, mode="cancel-reuse", tls=True)
            self.client(port, mode="multiplex", tls=True, size=65537)

    def test_nurl_client_rejects_malformed_responses(self):
        initial = [(":status", "200"), ("content-type", "application/grpc")]
        framed = b"\0\0\0\0\1a"
        cases = [
            ("missing status", initial, framed, [], 2),
            ("unknown status", initial, b"", [("grpc-status", "99")], 2),
            ("malformed status", initial, b"", [("grpc-status", "00")], 2),
            ("duplicate status", initial, b"", [("grpc-status", "0"), ("grpc-status", "0")], 2),
            ("early status", initial+[("grpc-status", "0")], framed, [("grpc-status", "0")], 13),
            ("HTTP fallback", [(":status", "403"), ("content-type", "application/grpc")], b"", [], 7),
            ("explicit status overrides HTTP", [(":status", "503"), ("content-type", "application/grpc")], b"", [("grpc-status", "7")], 7),
            ("rich default code mismatch", initial, b"", [("grpc-status", "3"), ("grpc-status-details-bin", "EgFi")], 13),
            ("wrong content", [(":status", "200"), ("content-type", "text/html")], b"", [], 2),
            ("truncated frame", initial, b"\0\0\0\0\3a", [("grpc-status", "0")], 13),
            ("invalid flag", initial, b"\2\0\0\0\0", [("grpc-status", "0")], 13),
            ("missing encoding", initial, b"\1\0\0\0\0", [("grpc-status", "0")], 13),
            ("oversized length", initial, b"\0\x7f\xff\xff\xff", [("grpc-status", "0")], 8),
            ("unary empty", initial, b"", [("grpc-status", "0")], 13),
            ("unary multiple", initial, framed+framed, [("grpc-status", "0")], 13),
            ("rich status mismatch", initial, b"", [("grpc-status", "3"), ("grpc-status-details-bin", "CAQ=")], 13),
        ]
        for name, headers, body, trailers, expected in cases:
            with self.subTest(case=name), socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                listener.listen()
                failures = []

                def peer():
                    try:
                        with listener.accept()[0] as sock:
                            sock.settimeout(10)
                            conn = h2.connection.H2Connection(config=h2.config.H2Configuration(client_side=False))
                            conn.initiate_connection()
                            sock.sendall(conn.data_to_send())
                            ended = False
                            while not ended:
                                data = sock.recv(65536)
                                if not data:
                                    raise AssertionError("client closed before request")
                                for event in conn.receive_data(data):
                                    if isinstance(event, h2.events.DataReceived):
                                        conn.acknowledge_received_data(event.flow_controlled_length, event.stream_id)
                                    if isinstance(event, h2.events.StreamEnded):
                                        sid = event.stream_id
                                        ended = True
                                sock.sendall(conn.data_to_send())
                            conn.send_headers(sid, headers, end_stream=not body and not trailers)
                            if body:
                                conn.send_data(sid, body, end_stream=not trailers)
                            if trailers:
                                conn.send_headers(sid, trailers, end_stream=True)
                            sock.sendall(conn.data_to_send())
                            try:
                                while sock.recv(65536):
                                    pass
                            except ConnectionResetError:
                                pass
                    except Exception as error:
                        failures.append(error)

                worker = threading.Thread(target=peer, daemon=True)
                worker.start()
                try:
                    self.client(listener.getsockname()[1], status=expected, size=1)
                finally:
                    worker.join(timeout=12)
                self.assertFalse(worker.is_alive(), name)
                self.assertEqual(failures, [], name)

    def test_nurl_client_tls_rejects_untrusted_certificate(self):
        with self.oracle_server(tls=True) as port:
            run = subprocess.run([str(self.bins["client"]), str(port), "/test.Echo/Unary",
                                  "unary", "identity", "tls", "0", "1"],
                                 cwd=ROOT, env={**self.env, "SSL_CERT_FILE": "/dev/null"},
                                 capture_output=True, text=True, timeout=15)
            self.assertNotEqual(run.returncode, 0)
            self.assertIn("H2CTls", run.stderr)
            self.assertNotIn("Sanitizer", run.stderr)
            self.client(port, tls=True)

    def test_nurl_peers_large_bidirectional_tls(self):
        with self.nurl_server(tls=True) as address:
            self.client(int(address.rsplit(":", 1)[1]), "Bidi", "bidi", tls=True, size=1048577)

    def test_nurl_server_all_call_shapes(self):
        payload = b"\x00\xff\x12test"
        with self.nurl_server() as address, self.channel(address) as channel:
            metadata = (("trace-bin", b"\0\xff"), ("x-repeat", "one"), ("x-repeat", "two"))
            unary = channel.unary_unary("/test.Echo/Unary")
            response, call = unary.with_call(payload, metadata=metadata, timeout=10)
            self.assertEqual(response, payload)
            self.assertEqual([item for item in call.initial_metadata() if item[0] == "trace-bin"],
                             [("trace-bin", b"\0\xff")])
            self.assertEqual([value for key, value in call.initial_metadata() if key == "x-repeat"],
                             ["one", "two"])
            self.assertIn(("finished", "yes"), call.trailing_metadata())
            self.assertEqual(list(channel.unary_stream("/test.Echo/ServerStream")(payload, timeout=10)),
                             [payload] * 3)
            self.assertEqual(channel.stream_unary("/test.Echo/ClientStream")(iter([payload] * 3), timeout=10),
                             payload * 3)
            # The request producer cannot send item 2 until response 1 exists.
            acknowledgements = queue.Queue()

            def requests():
                for _ in range(3):
                    yield payload
                    acknowledgements.get(timeout=5)

            replies = channel.stream_stream("/test.Echo/Bidi")(requests(), timeout=10)
            for response in replies:
                self.assertEqual(response, payload)
                acknowledgements.put(True)

    def test_nurl_server_gzip_and_tls(self):
        with self.nurl_server("gzip", tls=True) as address, self.channel(address, tls=True) as channel:
            unary = channel.unary_unary("/test.Echo/Unary")
            for size in (0, 1, 262145):
                payload = bytes(range(256)) * (size // 256) + bytes(range(size % 256))
                self.assertEqual(unary(payload, compression=grpc.Compression.Gzip, timeout=15), payload)

    def test_nurl_server_status_deadline_and_reuse(self):
        with self.nurl_server() as address, self.channel(address) as channel:
            for method, code in (("Error", grpc.StatusCode.INVALID_ARGUMENT),
                                 ("Missing", grpc.StatusCode.UNIMPLEMENTED),
                                 ("Slow", grpc.StatusCode.DEADLINE_EXCEEDED)):
                with self.assertRaises(grpc.RpcError) as caught:
                    channel.unary_unary(f"/test.Echo/{method}")(b"", timeout=.15)
                self.assertEqual(caught.exception.code(), code)
                if method == "Error":
                    self.assertEqual(caught.exception.details(), "bad % ä")
                    self.assertIn(("grpc-status-details-bin", b"\x08\x03"), caught.exception.trailing_metadata())
            self.assertEqual(channel.unary_unary("/test.Echo/Unary")(b"alive", timeout=10), b"alive")

    def test_nurl_server_multiplex(self):
        with self.nurl_server() as address, self.channel(address) as channel:
            unary = channel.unary_unary("/test.Echo/Unary")
            payloads = [bytes([index]) * (65537 + index) for index in range(12)]
            pending = [unary.future(payload, timeout=15) for payload in payloads]
            self.assertEqual([call.result() for call in pending], payloads)

    def test_fragmented_frames_and_trailers_only_errors(self):
        with self.nurl_server() as address:
            host, port = address.rsplit(":", 1)
            with socket.create_connection((host, int(port)), timeout=10) as sock:
                conn = h2.connection.H2Connection(config=h2.config.H2Configuration(client_side=True,
                                                                                  header_encoding="utf-8"))
                conn.initiate_connection()
                sock.sendall(conn.data_to_send())
                headers = [(":method", "POST"), (":scheme", "http"), (":authority", address),
                           (":path", "/test.Echo/Unary"), ("content-type", "application/grpc"),
                           ("te", "trailers")]
                conn.send_headers(1, headers)
                framed = b"\0" + struct.pack(">I", 3) + b"\0\xffa"
                for byte in framed:
                    conn.send_data(1, bytes([byte]))
                conn.end_stream(1)
                headers[3] = (":path", "/test.Echo/Unary")
                conn.send_headers(3, headers)
                conn.send_data(3, b"\2\0\0\0\0", end_stream=True)
                sock.sendall(conn.data_to_send())
                received = bytearray()
                statuses = {}
                ended = set()
                while len(ended) < 2:
                    data = sock.recv(65536)
                    self.assertTrue(data)
                    for event in conn.receive_data(data):
                        if isinstance(event, h2.events.DataReceived):
                            if event.stream_id == 1:
                                received.extend(event.data)
                            conn.acknowledge_received_data(event.flow_controlled_length, event.stream_id)
                        if isinstance(event, (h2.events.ResponseReceived, h2.events.TrailersReceived)):
                            for name, value in event.headers:
                                if name == "grpc-status":
                                    statuses[event.stream_id] = value
                        if isinstance(event, h2.events.StreamEnded):
                            ended.add(event.stream_id)
                    sock.sendall(conn.data_to_send())
                self.assertEqual(received, framed)
                self.assertEqual(statuses, {1: "0", 3: "13"})


    def test_nurl_server_protocol_rejections_and_reuse(self):
        """Malformed RPCs terminate their stream and leave HPACK/connection usable."""
        import gzip

        with self.nurl_server() as address:
            host, port = address.rsplit(":", 1)
            with socket.create_connection((host, int(port)), timeout=10) as sock:
                conn = h2.connection.H2Connection(config=h2.config.H2Configuration(
                    client_side=True, header_encoding="utf-8"))
                conn.initiate_connection()
                sock.sendall(conn.data_to_send())
                next_id = 1

                def exchange(extra=(), body=b"\0\0\0\0\1x", method="POST",
                             path="/test.Echo/Unary", content_type="application/grpc",
                             te=True):
                    nonlocal next_id
                    sid = next_id
                    next_id += 2
                    headers = [(":method", method), (":scheme", "http"),
                               (":authority", address), (":path", path),
                               ("content-type", content_type)]
                    if te:
                        headers.append(("te", "trailers"))
                    conn.send_headers(sid, headers + list(extra))
                    conn.send_data(sid, body, end_stream=True)
                    sock.sendall(conn.data_to_send())
                    received = bytearray()
                    status = None
                    http_status = None
                    ended = False
                    while not ended:
                        wire = sock.recv(65536)
                        self.assertTrue(wire, "server closed the connection for an RPC error")
                        for event in conn.receive_data(wire):
                            if isinstance(event, h2.events.DataReceived):
                                if event.stream_id == sid:
                                    received.extend(event.data)
                                conn.acknowledge_received_data(event.flow_controlled_length,
                                                               event.stream_id)
                            if (isinstance(event, (h2.events.ResponseReceived,
                                                   h2.events.TrailersReceived))
                                    and event.stream_id == sid):
                                for name, value in event.headers:
                                    if name == "grpc-status":
                                        status = int(value)
                                    if name == ":status":
                                        http_status = int(value)
                            if isinstance(event, h2.events.StreamEnded) and event.stream_id == sid:
                                ended = True
                            self.assertNotIsInstance(event, h2.events.ConnectionTerminated)
                        sock.sendall(conn.data_to_send())
                    return status, http_status, bytes(received)

                bomb = gzip.compress(b"x" * (4194304 + 1))
                cases = [
                    ("method", {"method": "GET"}, 12),
                    ("path", {"path": "/invalid-method"}, 12),
                    ("content-type", {"content_type": "application/grpc-web"}, 13),
                    ("missing-te", {"te": False}, 3),
                    ("encoding", {"extra": [("grpc-encoding", "br")]}, 12),
                    ("duplicate-timeout", {"extra": [("grpc-timeout", "1S"),
                                                      ("grpc-timeout", "2S")]}, 3),
                    ("timeout-unit", {"extra": [("grpc-timeout", "1q")]}, 3),
                    ("zero-timeout", {"extra": [("grpc-timeout", "0n")]}, 4),
                    ("binary-metadata", {"extra": [("trace-bin", "!!!!")]}, 13),
                    ("metadata-limit", {"extra": [("large", "x" * 9000)]}, 8),
                    ("compressed-flag", {"body": b"\2\0\0\0\0"}, 13),
                    ("undeclared-compression", {"body": b"\1\0\0\0\0"}, 13),
                    ("truncated-prefix", {"body": b"\0\0\0"}, 13),
                    ("truncated-message", {"body": b"\0\0\0\0\3ab"}, 13),
                    ("message-limit", {"body": b"\0" + struct.pack(">I", 4194305)}, 8),
                    ("gzip-corruption", {"extra": [("grpc-encoding", "gzip")],
                                         "body": b"\1\0\0\0\5hello"}, 13),
                    ("gzip-expansion-limit", {"extra": [("grpc-encoding", "gzip")],
                                              "body": b"\1" + struct.pack(">I", len(bomb)) + bomb}, 8),
                    ("deadline", {"extra": [("grpc-timeout", "20m")],
                                  "path": "/test.Echo/Slow"}, 4),
                ]
                for label, kwargs, expected in cases:
                    with self.subTest(label=label):
                        status, http_status, _ = exchange(**kwargs)
                        self.assertEqual(status, expected)
                        if label == "content-type":
                            self.assertEqual(http_status, 415)
                        self.assertEqual(exchange(), (0, 200, b"\0\0\0\0\1x"))


if __name__ == "__main__":
    unittest.main()
