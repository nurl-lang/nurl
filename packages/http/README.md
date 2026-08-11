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

## The App API

Construction & serving:

| Call | Effect |
| --- | --- |
| `( http_app_new )` → `*HttpApp` | create an app (free with `http_app_free`) |
| `( http_app_listen a host port )` → `i` | bind + serve until closed (SIGINT/SIGTERM/error) |
| `( http_app_listen_tls a host port cert key )` → `i` | same, over TLS (PEM paths; EC or RSA leaf) |

Routing (handlers are `( @ HttpResponse HttpRequest Params )`):

| Call | |
| --- | --- |
| `( http_app_get a pattern h )` | also `http_app_post` / `put` / `patch` / `delete` |
| `( http_app_route a method pattern h )` | any method |
| `( http_app_use_router a router )` | adopt a pre-built `Router` (keeps it socket-testable) |
| `( http_app_router a )` → `Router` | the embedded router |

Patterns use the stdlib router: `:name` captures a segment (read with
`params_get`), `*rest` is a tail wildcard.

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
