# http — the unified HTTP server interface for NURL

One dependency for anything that needs to **serve** HTTP. NURL's stdlib
already ships a complete HTTP stack — sockets + TLS, a request parser, a
response builder, a keep-alive server with worker pools and DoS limits, a
router, static-file serving, and auth / jwt / multipart / middleware /
websocket helpers. What it *doesn't* ship is the ~40 lines of glue every
server re-invents: bind → build a router → install a shutdown signal → wrap
the handler in logging / CORS / panic-recovery → run the keep-alive loop.

`http` is that glue, as an ergonomic, dependency-importable facade — plus
the whole stdlib surface pulled in transitively, so you `$`-include one file
and have everything a handler needs in scope.

## Hello, server

```nurl
$ `deps/http/src/http.nu`

@ main → i {
    : *HttpApp a ( http_app_new )
    ( http_app_get a `/` \ HttpRequest req Params p → HttpResponse {
        ^ ( response_text 200 `hello` )
    } )
    ( http_app_get a `/hi/:name` \ HttpRequest req Params p → HttpResponse {
        : String o ( string_from `hi ` )
        ?? ( params_get p `name` ) { T n → { ( string_push_str o ( string_data n ) ) ( string_free n ) } F j → { ( string_free j ) } }
        : HttpResponse r ( response_text 200 ( string_data o ) )
        ( string_free o )
        ^ r
    } )
    ^ ( http_app_listen a `127.0.0.1` 8080 )   // blocks; returns an exit code
}
```

## Capabilities

One `http_app_listen_tls` call gives a server every protocol a client
might ask for, chosen per connection by the client, with nothing to
configure:

| | What the client gets | How it is chosen |
| --- | --- | --- |
| **HTTP/1.1** | keep-alive, pipelining, chunked bodies, streaming responses | the default on both listeners |
| **HTTP/2** (RFC 9113) | multiplexed streams, HPACK, flow control | ALPN `h2` on the TLS listener; the connection preface on the plaintext listener (prior knowledge) |
| **HTTP/3** (RFC 9114) | QUIC (RFC 9000/9001/9002) over UDP on the same port, QPACK, 0-RTT-less 1-RTT handshake | `Alt-Svc: h3` on every TCP response; a client that already knows (curl `--http3`, a browser on its second visit) connects over UDP directly |
| **Post-quantum key exchange** | X25519MLKEM768 (hybrid ML-KEM-768, RFC 9370 group 0x11ec) | the server's first preference on TCP and QUIC alike; a client without it (pre-2024 stacks) falls back to X25519 or P-256 |
| **Post-quantum authentication** | an ML-DSA (FIPS 204) certificate, CertificateVerify signed with `mldsa44/65/87` | `http_app_set_pq_cert`: the ML-DSA leaf is shown to every client whose `signature_algorithms` lists its scheme (RFC 8446 §4.4.2.2), the classical leaf to the rest — so a post-quantum certificate never turns a client away |
| **Classical authentication** | EC P-256 (`ecdsa_secp256r1_sha256`) or RSA (`rsa_pss_rsae_sha256`) leaf, full chain | the `cert` / `key` pair of `http_app_listen_tls`, key form auto-detected |
| **Session resumption** | TLS 1.3 tickets, one shared ticket key per process | offered to every client that asks (`psk_key_exchange_modes`) |

The whole stack — TCP/TLS 1.3, QUIC, HTTP/1.1, HTTP/2, HTTP/3, ML-KEM,
ML-DSA, X.509 — is pure NURL over a libc socket: no OpenSSL, no nghttp2,
no quiche. With both post-quantum pieces negotiated, no asymmetric
operation in the handshake is one a quantum computer breaks: the traffic
keys cannot be recovered from a recording, and the server cannot be
impersonated. Public CAs do not issue ML-DSA certificates yet; mint a
self-signed one with `x509_selfsigned_mldsa` (`std/x509_gen.nu`) or run
the [pki-server](../pki-server) package as a private CA.

```nurl
( http_app_set_pq_cert a `certs/mldsa65.pem` `certs/mldsa65.key` )   // optional
^ ( http_app_listen_tls a `0.0.0.0` 443 `certs/fullchain.pem` `certs/privkey.pem` )
```

`tcp_tls_sig_scheme conn` / `tcp_is_post_quantum conn` (`std/net.nu`)
report what a given connection settled on.

## The App API

Construction & serving:

| Call | Effect |
| --- | --- |
| `( http_app_new )` → `*HttpApp` | create an app (free with `http_app_free`) |
| `( http_app_listen a host port )` → `i` | bind + serve until closed (SIGINT/SIGTERM/error); HTTP/1.1 and HTTP/2 (prior knowledge) on the same port |
| `( http_app_listen_tls a host port cert key )` → `i` | same, over TLS (PEM paths; EC, RSA or ML-DSA leaf, auto-detected); ALPN `h2 http/1.1`, so HTTP/2-capable clients get HTTP/2; **HTTP/3 (QUIC) on the same port over UDP**, announced with `Alt-Svc` on the TCP responses |
| `( http_app_set_http3 a 0 )` → `v` | keep a TLS listener TCP-only (no UDP socket, no Alt-Svc); default 1 |
| `( http_app_set_pq_cert a cert key )` → `v` | a second, **post-quantum identity** (ML-DSA-44/65/87 chain + PKCS#8 key) served beside the classical pair; each client is shown the one its `signature_algorithms` can verify — see [Capabilities](#capabilities) |

Routing (handlers are `( @ HttpResponse HttpRequest Params )`):

| Call | |
| --- | --- |
| `( http_app_get a pattern h )` | also `http_app_post` / `put` / `patch` / `delete` |
| `( http_app_route a method pattern h )` | any method |
| `( http_app_use_router a router )` | adopt a pre-built `Router` (keeps it socket-testable) |
| `( http_app_use a middleware )` | wrap the app's whole dispatch in a handler of your own — see below |
| `( http_app_router a )` → `Router` | the embedded router |

Patterns use the stdlib router: `:name` captures a segment (read with
`params_get`), `*rest` is a tail wildcard.

### Middleware

`http_app_use` takes a function from the app's dispatch to the handler
actually served, and is the seam for anything the built-in layers do not
do — a concurrency gate in front of an expensive route, a per-IP budget,
an auth check:

```nurl
( http_app_use a \ ( @ HttpResponse HttpRequest ) inner → ( @ HttpResponse HttpRequest ) {
    ^ \ HttpRequest req → HttpResponse {
        ? ( is_heavy req ) { ( sem_acquire gate ) } {}
        : HttpResponse r ( inner req )
        ? ( is_heavy req ) { ( sem_release gate ) } {}
        ^ r
    }
} )
```

A request reaches `[alt-svc] → [log] → [cors] → your middleware → route /
static`, so CORS preflights and the access log still see the requests a
gate holds. One middleware per app — a second call replaces the first;
a chain composes inside the one closure. The wrapper and the handler it
returns must outlive `http_app_listen`.

Configuration (call before serving):

| Call | Default | |
| --- | --- | --- |
| `( http_app_static_dir a dir )` | off | serve files for unmatched GET/HEAD (traversal-safe) |
| `( http_app_cors a )` | off | permissive CORS + 204 OPTIONS preflight |
| `( http_app_logging a )` | off | access log (method path → status) to stderr |
| `( http_app_recover a on )` | — | deprecated no-op: panic → 500 is an unconditional stdlib-server guarantee |
| `( http_app_workers a n )` | 0 | 0 = single-threaded keep-alive; n > 0 = worker pool |
| `( http_app_idle_ms a ms )` | 5000 | keep-alive idle timeout |
| `( http_app_body_max a bytes )` | 10 MiB | request-body cap (parser answers 413 above it) — raise for upload endpoints |
| `( http_app_head_max a bytes )` | 8 KiB | request-head cap |
| `( http_app_max_keepalive a n )` | 1000 | per-connection request reuse cap (0 = close after one) |
| `( http_app_request_timeout a ms )` | off | per-request wall-clock budget → stock 504 on overrun |
| `( http_app_quiet a )` | off | suppress the startup banner |

Everything under the facade is the untouched stdlib implementation, in scope
from the one include: `HttpRequest` / `HttpResponse`, `response_text` /
`response_json` / `response_new` / `response_set_header` / …, `Router` /
`params_get`, plus the auth, jwt, multipart and websocket helpers.

## Wrapping an existing router

A server that already builds a `Router` (e.g. to keep every route testable
without a socket) drops onto the facade with one seam:

```nurl
@ my_service_router → Router { ... router_post r `/x` h ... ^ r }

@ my_serve s host i port → i {
    : *HttpApp a ( http_app_new )
    ( http_app_use_router a ( my_service_router ) )   // adopt the routes
    : i rc ( http_app_listen a host port )            // facade owns the glue
    ( http_app_free a )
    ^ rc
}
```

The `anomaly` package's HTTP service is served exactly this way.

## Memory model

`http_app_new` returns a heap `*HttpApp`, mutable across the registration
calls; free it with `http_app_free`. The embedded `Router` holds a stable
`Vec` handle, so registrations accumulate correctly. `http_app_listen`
**moves** the bound listener into the server and stops it on return.

## Tests

`./tests/http_test.sh` builds `tests/smoke.nu` (a server exercising routing,
path params, POST bodies, static fallback, CORS, and panic recovery) and
drives it over curl — including that the keep-alive loop survives a handler
panic.
