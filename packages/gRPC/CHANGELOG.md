# Changelog

## [0.2.4] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held.

### Changed

- The server updates a call in its table slot, through the slot, where
  it copied the record out, changed the copy and wrote it back by hand
  (`mem_put_back`). A queue, trailers or decoder input that a write
  replaces is dropped by the write; nothing is released by hand. The
  test fixture's call table works the same way.

## [0.2.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.2.2 does not compile under it.

### Changed

- `GrpcClient` keeps its state in an `Arc` (stdlib/std/arc.nu) instead of
  an `rcbox`. The share and drop hooks are ordinary safe functions — the
  Arc does the counting — and so are the constructors that build one from
  a whole value; every copy is still the same state, and its last owner
  releases it.
- One fewer function is `unsafe` than in 0.2.2.

## [0.2.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.2.1 does not compile under 0.72.0.

### Changed

- The server reads a call out of its table as a borrow of the table
  alone, and reads it again after each write to its slot, as 0.72.0's
  exclusivity rules require; a received trailer block goes into the
  table at once. Metadata values are base64-encoded with
  `b64_encode_string`. Nothing changes on the wire.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.2.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.2.0 does
not compile under 0.71.0.

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
