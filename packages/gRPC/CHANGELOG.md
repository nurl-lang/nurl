# Changelog

## [0.2.0] — 2026-10-03

Nothing is released by hand any more.

### Changed (breaking)

- `GrpcClient` is a handle over an rcbox (`: GrpcClient { s ctl }`) instead
  of a plain struct with `transport` / `scheme` / `authority` fields: every
  copy is the same client, and each `GrpcCall` holds a share of it (the
  call's `transport` field became `client`), so the transport outlives
  every call on it. The last owner disconnects a transport the client
  opened (`grpc_client_connect_*`); a transport lent with
  `grpc_client_from_h2` stays its owner's. Previously a client that was not
  closed by hand leaked its connection, and closing it before its calls
  left them on a freed transport.
- A dropped `GrpcCall` cancels and releases its stream (`% Drop`); its
  decoder, metadata and status go with the drop glue.
- A dropped `GrpcServer` flushes and releases its HTTP/2 connection state
  (`% Drop GrpcServer` → `h2_conn_free`), and its calls with it.
- `grpc_client_close`, `grpc_call_free`, `grpc_server_free`,
  `grpc_server_event_free`, `grpc_unary_response_free`,
  `grpc_metadata_free`, `grpc_status_free`, `grpc_error_free`,
  `grpc_message_free` and `grpc_decoder_free` are no-op optional early
  releases (the value is dropped at the call); every redundant release in
  the library, tests and fixtures is gone.

### Performance

- Client instructions unchanged (−0.02 % over 400 unary + 100
  server-streaming calls).

Requires NURL 0.69.0.

## 0.1.1

`GrpcCall` is dropped automatically (`% Drop`), the call-failure path takes its error by `sink`, and the call table's getter/setter pair writes back with `mem_put_back` (NURL 0.67.0 ownership, #1141/#1142).
