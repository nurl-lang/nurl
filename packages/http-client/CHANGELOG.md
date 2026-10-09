# Changelog

## [0.3.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.3.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

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
