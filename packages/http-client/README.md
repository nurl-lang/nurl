# http-client — the unified HTTP client interface for NURL

One dependency for anything that needs to **fetch** over HTTP. NURL's
stdlib already ships a complete client stack — pure-NURL TLS 1.3 (with
X25519MLKEM768 hybrid key exchange and ML-DSA certificate chains), an
HTTP/1.1 keep-alive client, a multiplexed HTTP/2 client, an RFC 6265
cookie jar, and gzip / deflate. What it *doesn't* ship is the glue every
program re-invents: pick the protocol the server actually offers, pool
the connection to reuse it, carry cookies, follow redirects, decode the
body.

`http-client` is that glue, as an ergonomic, dependency-importable
facade — the mirror image of the [`http`](../http) server package.

## Hello, request

```nurl
$ `deps/http-client/src/http_client.nu`

@ main → i {
    : *HttpClient c ( http_client_new )
    ?? ( http_client_get c `https://example.org/` ) {
        T r → {
            ( nurl_print_int ( http_client_status r ) )
            ( http_response_free r )
        }
        F e → { ( nurl_eprintln ( http_client_err_name e ) ) }
    }
    ( http_client_free c )
    ^ 0
}
```

## What one client gives you, with nothing configured

| Feature | How |
| --- | --- |
| **Automatic protocol** | an `https` origin is dialled with ALPN `h2 http/1.1`; whichever the server picks is what the client speaks — HTTP/2 multiplexed, or HTTP/1.1 with keep-alive. Plaintext `http` is HTTP/1.1. |
| **Post-quantum TLS** | the stdlib client offers X25519MLKEM768 first and verifies ML-DSA (44/65/87) certificate chains, so a post-quantum server is used as such automatically. `http_client_last_pq c` reports it. |
| **Connection pooling** | one live connection per `(scheme, host, port)` — the h2 connection is multiplexed, the h1 connection is kept alive and reused. |
| **TLS session resumption** | tickets are cached per host and offered on the next connection, so a repeat visit skips the certificate and the signature. |
| **Redirects** | 3xx are followed (up to `max_redirects`); a 303, and a 301/302 on a POST, become a bodyless GET, exactly as browsers do. Relative `Location`s resolve per RFC 3986 §5.2. |
| **Cookies** | a built-in RFC 6265 jar stores `Set-Cookie` and sends `Cookie` on matching requests. |
| **Compression** | `Accept-Encoding: gzip, deflate` is offered and the body is decoded transparently, with an output cap against decompression bombs. |

## Configuration

```nurl
: *HttpClient c ( http_client_new )
( http_client_set_verify c F )          // pinned / self-signed / test servers
( http_client_set_timeout c 5000 )      // per read/write deadline, ms (0 = none)
( http_client_set_max_redirects c 3 )
( http_client_set_decompress c F )       // leave bodies as the wire carried them
( http_client_set_body_max c 1048576 )   // cap the decoded body; larger → HcTooLarge
( http_client_set_user_agent c `myapp/1.0` )
```

## Verbs

```nurl
( http_client_get    c url )
( http_client_head   c url )
( http_client_delete c url )
( http_client_post   c url body content_type )   // body is a ( Vec u ), borrowed
( http_client_put    c url body content_type )
( http_client_patch  c url body content_type )
( http_client_post_str c url `{"a":1}` `application/json` )
( http_client_request c method url headers body ) // full control; headers consumed
```

Every call returns `!HttpResponse HttpClientErr` — the same `HttpResponse`
the `http` server package builds, with `http_client_status`,
`http_client_header` and `http_client_body_str` helpers, freed with
`http_response_free`.

## Evidence

```nurl
( http_client_last_proto c )   // 1 HTTP/1.1, 2 HTTP/2, 0 none yet
( http_client_last_pq c )      // T when the key exchange was post-quantum
```

## Where the line is drawn

Following the same two-layer split as the `http` package: the **stdlib**
owns the primitives a package cannot provide (the TLS client with an ALPN
preference list and one full-knob connect, keep-alive and honoured
timeouts in the HTTP/1.1 transport, the HTTP/2 client, the codecs); this
package owns the **glue** (one `HttpClient`, per-origin pooling, protocol
selection, the cookie jar wired in, redirects, decompression, a unified
response and error type). The toolchain's own consumers (nurlpkg, hub)
cannot depend on a package, so they benefit from the stdlib half; this
package versions independently of the toolchain.

HTTP/3 over QUIC is not yet a client role in the stdlib (the server side
is complete); when it lands, this facade gains it behind the same
`Alt-Svc`-driven upgrade without an API change.

## Tests

`./tests/client_test.sh` builds a server on the `http` package and drives
the facade against it over both plaintext and TLS: protocol selection,
connection reuse, redirects and the redirect cap, cookies, gzip decoding,
POST bodies, and post-quantum key exchange. Requires `openssl` (to mint a
test certificate) and `curl` (readiness probe).

## License

MIT OR Apache-2.0.
