# gRPC

Native gRPC over HTTP/2 for NURL. The library transports protobuf bytes and
supports unary, client streaming, server streaming and bidirectional calls.
TCP, TLS, HTTP/2, HPACK, gzip and protobuf use NURL's standard library.
Requires NURL 0.65.0 or newer.

```toml
[dependencies]
grpc = "^0"
```

Import `deps/grpc/src/grpc.nu`, or `client.nu` / `server.nu` separately.
The repository directory is `packages/gRPC`; the registry name is `grpc`.
Run `nurlpkg install` from the consumer's directory after adding the dependency.

## Client

```nurl
$ `deps/grpc/src/client.nu`

@ echo GrpcClient client ( Vec u ) request → !v GrpcError {
    : ( Vec Header ) metadata ( grpc_metadata_new )
    ; { ( grpc_metadata_free metadata ) }
    : ~ GrpcCallOptions options ( grpc_call_options )
    = . options timeout_ns 5000000000
    : GrpcUnaryResponse reply \ ( grpc_unary client
        `/example.Echo/Unary` request metadata options )
    // Decode reply.data with stdlib/ext/protobuf.nu and the service schema.
    ( grpc_unary_response_free reply )
    ^ @ !v GrpcError { T 0 }
}
```

`grpc_client_connect_tls(host, port, verify)` verifies certificates when
`verify` is true and requires ALPN `h2`. `SSL_CERT_FILE` selects a private CA
bundle. `grpc_client_connect_h2c(host, port)` explicitly selects cleartext
HTTP/2 prior knowledge. Release calls before `grpc_client_close(client)`.

For streaming, open a `GrpcCall` with `grpc_call_open(client, path, metadata,
options)`, send borrowed payloads with `grpc_call_send`, and finish the request
side with `grpc_call_half_close`. `grpc_call_receive` returns an owned
`GrpcMessage`: `present = true` includes an actual message, even when its
payload is empty. `present = false` means successful completion. A non-OK
status returns `GrpcError` after any preceding response messages. Free each
message with `grpc_message_free` and the call with `grpc_call_free`.

Requests and responses may overlap: bidirectional calls can receive before
half-closing. A client and its calls have one owner and one driver; concurrent
calls share HTTP/2 streams, and the application drives their progress. Sending
into a full bounded queue reports `RESOURCE_EXHAUSTED`; receive/pump existing
traffic before retrying. Calls are never retried automatically.

Call options specify the deadline duration in nanoseconds (`0` means no
deadline), send/receive message limits, metadata limit, and `GRPC_IDENTITY` or
`GRPC_GZIP` request compression. Default message size is 4 MiB; default metadata
size is 8 KiB. Limits apply to both compressed and decompressed message bytes.
`grpc_call_cancel` cancels one call; freeing an unfinished call cancels it too.

## Server

Use `grpc_server_new(tcp, limits)` on an accepted HTTP/2 connection, then drive
`grpc_server_next` with a mutable `GrpcServer`. `grpc_server_limits()` provides
bounded defaults. Events carry a stream ID and one of:

- `grpc_server_event_open`: method path and application metadata.
- `grpc_server_event_message`: one owned message, independent of DATA framing.
- `grpc_server_event_half_close`: the request sender has finished; metadata
  contains any request trailers.
- `grpc_server_event_cancelled`: cancellation or deadline expiration.
- `grpc_server_event_control`: transport progress; the driver continues.
- `grpc_server_event_closed`: the connection has ended.

Free events with `grpc_server_event_free`. Send initial metadata with
`grpc_server_send_metadata`, messages with `grpc_server_send`, and finish with
`grpc_server_finish(server, stream_id, status, trailing_metadata)`. Finishing
queues mandatory status trailers after pending messages; errors may finish
without messages. `grpc_server_flush` advances queued writes without reading.
Application handlers decide method routing, cardinality, authorization and
protobuf schema rules. Stop application work on cancellation, and keep slow
work out of the connection's driver. Free the server, then close its borrowed
TCP connection.

For scheduled messages or application work, `grpc_server_next_until(server,
deadline_ns)` uses an absolute monotonic polling deadline and returns a control
event when it expires. This does not cancel RPCs. `grpc_server_deadline(server,
stream_id)` returns the RPC's absolute deadline (`0` means none), and
`grpc_server_is_cancelled` lets work check cancellation or expiry before
continuing. The driver must keep polling to observe peer cancellations.

For TLS listeners use `tcp_listen_tls_with_alpn(..., "h2")` (NURL source uses
backticks around string literals). The [test server](tests/fixtures/server.nu) shows
all four call patterns with cleanup; it deliberately accepts one connection
so sanitizer tests can check the whole lifecycle.

## Metadata and errors

Metadata is a `Vec[Header]`. Add printable ASCII with `grpc_metadata_add`, and
binary values with `grpc_metadata_add_binary`; binary names end in `-bin`.
Application binary values are raw, binary-safe Strings. The library handles
padded/unpadded Base64 and comma-joined binary values on the wire. Duplicate
metadata is preserved. Reserved transport keys cannot be injected through
application metadata.

`GrpcError` owns its message; release it with `grpc_error_free`. All 17 status
codes are available as `GRPC_*` constants. `GrpcStatus` also carries optional
serialized `google.rpc.Status` details. The library checks that a details code
agrees with `grpc-status`. Status messages use UTF-8 percent encoding; malformed
percent escapes remain readable. Missing status never counts as success.

The library follows the [gRPC HTTP/2 protocol](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md)
and [HTTP-to-gRPC fallback status mapping](https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md).
It does not generate code from `.proto` files. Use the
[standard protobuf codec](https://github.com/nurl-lang/nurl/blob/main/docs/stdlib/protobuf.md) for service-specific
message readers and writers; the transport accepts any payload serializer.

## Validation

Run `nurlpkg test` from this package's directory to exercise its standalone
wire, metadata and compression tests. The peer programs in `tests/fixtures/`
are driven by the repository's interoperability suite:

```sh
python -m pip install -r packages/gRPC/tests/requirements.txt
python tools/tests/test_grpc.py
NURL_SAN=1 python tools/tests/test_grpc.py
```

The integration tests use the official gRPC C-core Python runtime in both
directions and an independent HTTP/2 peer for malformed/fractured messages.
The same suite runs under ASan, UBSan and leak detection. Standard-library
regressions additionally exercise HTTP/2 state, Base64 and compression against
independent reference implementations.

See [DEVELOPMENT.md](DEVELOPMENT.md) for release acceptance steps and coverage.
