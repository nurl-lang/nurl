# Changelog

## Unreleased

Follows the stdlib's HTTP/3 client handle: `h3_client_connect` now returns an
`H3Client` value (a handle that releases itself when its last owner goes)
instead of a `*H3Client`. An origin holds the handle while its QUIC connection
is pooled; a QUIC attempt that does not complete is released with its binding
instead of by an explicit free. No change to the facade's API.

`HttpClient` releases itself: `http_client_new` returns an `HttpClient`
handle (its state in an rcbox) instead of a `*HttpClient` the caller had to
free. Every copy of the handle is the same client; its last owner closes the
pooled connections and releases the pool, the cookie jar and the rest.
`http_client_free` stays as an optional early release. The origin records
are handles too — each one's drop closes the h2 / h1 connection it holds and
says goodbye to its QUIC connection — so nothing in the package frees by hand
any more. Callers change `*HttpClient` to `HttpClient`.

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
