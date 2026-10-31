# Changelog

## [0.3.7] — unreleased

Requires the NURL with std/net's `NetDialer` (`net_dial`, std/net_sim.nu's `netsim_dialer`) and stdlib/ext/http_pure.nu's `hp_conn_open_with`.

### Added

- `http_client_set_dialer c d` — origins are reached through a std/net `NetDialer`: the kernel's (the default) or a node of a simulated network (`netsim_dialer net node`), so the same client runs over the simulated wire unchanged (agora #249). `https` too: the handshake runs over the dialed connection (agora #250, #289), offering HTTP/1.1 there (HTTP/2's reader polls a socket handle); HTTP/3 is not tried through another dialer, never a quiet detour over the real network.

### Changed

- The plaintext transport underneath (http_pure's `HttpConn`) is a std/net `TcpConn` instead of a raw runtime socket handle. Measured on keep-alive GETs to a local hyper server: callgrind +144 instructions per request (+0.35 %, the std/net dispatch and the runtime's ownership check visiting the new handle fields), the same syscalls and allocations; wall clock within this VM's noise (median of 6: 21.5k → 21.9k requests/s).

## [0.3.6] — 2026-10-23

Requires NURL 0.73.0.

### Added

- `http_client_set_resume c F` stops offering cached TLS sessions: every
  new connection runs the full handshake. The session cache is
  process-wide, so a client could not opt out of resumption before — not
  for unlinkability across connections, and not to measure the full
  handshake (`bench/tls_bench` uses it).

## [0.3.5] — 2026-10-14

Requires NURL 0.73.0 (`slice_at`, `slice_put`, `rc_take`, `locked_take`).

### Changed

- Loops that read or wrote through `vec_data` pointers index slices (`slice_at` / `slice_put`, as fast as the pointers), and functions with nothing raw in them are no longer marked `unsafe`.
- No `unsafe` left (32 before; needs the stdlib's `hp_stream_open_on_vec`
  and `h3_client_ok`). The client's state is in a `Locked`: a request
  checks it out for its length, so requests through one shared client run
  one at a time — before, requests on two threads changed the pool and
  the jar through `arc_ptr` at once, and a pool that grew under one
  request left the other's origin record dangling. Each origin's
  connections are options (`?H2Client`, `?HttpConn`, `?H3Client`)
  instead of made-up null handles beside a `has_*` flag.
- `http_client_jar` returns a copy of the jar; `http_client_set_jar`
  (new) replaces it, to seed a session cookie.

## [0.3.4] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.3.3 does not compile under it.

### Changed

- A failed HTTP/2 attach no longer closes the connection by hand after handing it to the client: the client owns it then, and its drop closes it.
- A connection a pooled record gives up is moved out by the store that
  empties the field; the `mem_take` before it is gone.

## [0.3.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.3.2 does not compile under it.

### Changed

- `HcOrigin` and `HttpClient` keep their state in an `Arc`
  (stdlib/std/arc.nu) instead of an `rcbox`. The share and drop hooks are
  ordinary safe functions — the Arc does the counting — and so are the
  constructors that build one from a whole value; every copy is still the
  same state, and its last owner releases it.
- 2 fewer functions are `unsafe` than in 0.3.2.

## [0.3.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.3.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.3.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.3.0 does
not compile under 0.71.0.

## [0.3.0] — 2026-10-03

### Changed (breaking)

- `HttpClient` releases itself: `( http_client_new )` returns an `HttpClient`
  handle instead of a `*HttpClient` the caller had to free
  (`: *HttpClient c ( http_client_new )` → `: HttpClient c ( http_client_new )`).
  Every function that took `* HttpClient` (`http_client_get` / `_post` /
  `_request` / `_set_*` / `_jar` / `_last_proto` / …) takes `HttpClient`.
  Every copy of the handle is the same client; its last owner closes the
  pooled connections and releases the pool, the cookie jar and the rest.
  `http_client_free` stays as an optional early release.
- A returned `HttpResponse` is dropped with its binding — the examples no
  longer call `http_response_free`.

### Changed

- Follows the stdlib's HTTP/3 client handle: an origin holds its QUIC
  connection as an `H3Client` handle while it is pooled, and a QUIC attempt
  that does not complete is released with its binding. The per-origin
  records are handles too — each one's drop closes the h2 / h1 connection
  it holds and says goodbye to its QUIC connection — so nothing in the
  package frees by hand any more.

Requires NURL 0.69.0.

## 0.2.1

`http_client_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.2.0 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.

It also carries the write-deadline and nonblocking socket declarations that
came with toolchain 0.65.0: absolute TCP/TLS write deadlines, prepared
nonblocking writes and reads, and combined read/write readiness.
