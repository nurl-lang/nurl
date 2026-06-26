// stdlib/ext/http.nu — HTTP client (GET / POST / PUT / DELETE / PATCH
//                       + arbitrary outbound headers)
//
// Wraps the libcurl bridge in stdlib/runtime.c (§14). Synchronous only —
// one call blocks until the response arrives or the request times out
// (30 s by default; not user-tunable in this MVP).
//
// Build:
//   * Link the runtime against -lcurl when libcurl-dev is present.
//     build.sh, nurl.sh and run_tests.sh all detect libcurl via
//     pkg-config and pass `-DNURL_HAVE_LIBCURL` + `-lcurl`.
//   * On native Windows clang the runtime falls back to WinHTTP
//     (-lwinhttp), so http_get / http_post work out of the box on
//     Windows builds without bundling libcurl.
//   * wasm32-wasi targets compile but no HTTP backend is wired in;
//     every call returns HttpErr::HttpOther there.
//
// API (this revision):
//
//   ( header_new   s name s value )                  → Header
//   ( header_free  Header h )                        → v
//   ( header_blob_one s name s value )               → String  one-line blob
//
//   ( http_request   s method s url s body s headers_blob )
//                                                    → ! Response HttpErr
//   ( http_get       s url )                         → ! Response HttpErr
//   ( http_get_with_headers s url s headers_blob )   → ! Response HttpErr
//   ( http_post      s url s body s content_type )   → ! Response HttpErr
//   ( http_post_with_headers s url s body s content_type s headers_blob )
//                                                    → ! Response HttpErr
//   ( http_put       s url s body s content_type )   → ! Response HttpErr
//   ( http_delete    s url )                         → ! Response HttpErr
//   ( http_patch     s url s body s content_type )   → ! Response HttpErr
//
//   ( http_options_default )                         → HttpOptions
//   ( http_request_with_opts s method s url s body s headers_blob HttpOptions opt )
//                                                    → ! Response HttpErr
//   ( http_get_opts  s url HttpOptions opt )         → ! Response HttpErr
//   ( http_post_opts s url s body s content_type HttpOptions opt )
//                                                    → ! Response HttpErr
//
//   ( http_status   Response r )                     → i      shortcut
//   ( http_body_str Response r )                     → s      borrowed view
//   ( http_header_count Response r )                 → i
//   ( http_header_name  Response r i idx )           → s      borrowed
//   ( http_header_value Response r i idx )           → s      borrowed
//   ( response_free Response r )                     → v
//
// Header blob format ("headers_blob"):
//
//   "Name1: Value1\r\nName2: Value2\r\n"
//
// Pass an empty string `` (or NULL via raw FFI) to send no extra headers.
// Lines with no `:` are silently dropped both client-side and by the
// transport. The caller MUST own the blob long enough to outlive the
// http_request call; freeing the backing String afterwards is fine.
//
// http_post / http_put / http_patch take an explicit `content_type`
// argument — pass `` to omit the Content-Type header entirely (curl
// then picks "application/x-www-form-urlencoded" by default for POST,
// or no header at all for the custom verbs). Non-empty `content_type`
// is prepended to the headers blob the runtime sees.
//
// JSON convenience (`http_post_json url j`) lives in
// `stdlib/ext/http_json.nu` so HTTP-only callers don't pay the
// json.nu import cost.
//
// Memory model — single-owner, LLM-friendly:
//
//   * Each call returns a fresh OWNED Response. Caller MUST call
//     `response_free` exactly once on the Result-Ok path. (HttpErr
//     arms produced by these wrappers never carry a Response pointer.)
//   * The Response wraps a heap struct allocated by the C runtime
//     that owns its own copies of the body bytes and every header
//     name/value pair. `response_free` cascades to all of them.
//   * `http_status`, `http_body_str`, `http_header_*` return
//     BORROWED views (raw `s` pointers) into the response. Do not
//     free them; use `string_from` if you need a long-lived `String`
//     copy that outlives the Response.
//   * `headers_blob` arguments are BORROWED — never freed by the
//     runtime. Build them with `header_blob_one` + `string_concat`,
//     or pass a literal directly.
//   * `Header` + `header_new` / `header_free` are kept as a small
//     ergonomic helper for callers that want a typed pair, but the
//     transport itself reads only raw `s` blobs.
//
// Errors — `HttpErr` tags must match the C runtime constants
// in stdlib/runtime.c §14:
//
//   HttpConnect    1   TCP/SSL connect failed
//   HttpTimeout    2   request exceeded the 30 s ceiling
//   HttpTls        3   TLS handshake or cert verification failed
//   HttpDns        4   could not resolve hostname
//   HttpInvalidUrl 5   malformed URL or unsupported scheme
//   HttpOther      6   anything else / runtime built without libcurl

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/http_pure.nu`

// HttpErr tags — see stdlib/runtime.c §14 NURL_HTTP_ERR_*.
//
// Variants are prefixed (`Http*`) because NURL enum variants live in a
// flat global namespace — `Other` and `NotFound` already belong to
// IoErr, so reusing them here would collide at link time.
: | HttpErr { HttpConnect HttpTimeout HttpTls HttpDns HttpInvalidUrl HttpOther }

: Header { String name String value }

// Response wraps the runtime-owned RawResponse pointer (`s ptr`).
// All accessors go through the FFI helpers in runtime §14 so the
// representation can change without touching call sites.
: Response { s raw }

// HttpOptions bundles the per-request transport overrides that used to
// be hardcoded inside the libcurl orchestrator. Pass one to
// `http_request_with_opts` (or the `*_opts` convenience wrappers) for
// fine control over timeouts, redirect policy, TLS verification and the
// User-Agent header.
//
//   timeout_ms          total request budget; <=0 → 30000 (30 s)
//   connect_timeout_ms  TCP/TLS connect budget; <=0 → 10000 (10 s)
//   follow_redirects    1 = follow 3xx Location (default), 0 = don't
//   max_redirects       cap on followed hops; <0 → unlimited. Ignored
//                       when follow_redirects is 0.
//   verify_tls          1 = verify peer cert + hostname (default),
//                       0 = INSECURE (skip both — dev/self-signed only)
//   user_agent          override; empty `` → `nurl-http/0.1`. BORROWED
//                       (must outlive the call; never freed here).
//
// `user_agent` is a raw `s` (borrowed) so HttpOptions carries no owned
// resources — it needs no free function and is safe to pass by value.
//
// Note: these overrides apply only on the libcurl backend. The native
// WinHTTP / stub backends honour just the two timeouts; redirect / TLS /
// user-agent fields are silently ignored there.
: HttpOptions {
    i timeout_ms
    i connect_timeout_ms
    i follow_redirects
    i max_redirects
    i verify_tls
    s user_agent
}

// Default options: runtime-default timeouts, follow redirects with no
// cap, verify TLS, stock User-Agent.
@ http_options_default → HttpOptions {
    ^ @ HttpOptions { 0 0 1 -1 1 `` }
}

@ header_new s name s value → Header {
    : String n ( string_from name )
    : String v ( string_from value )
    ^ @ Header { n v }
}

@ header_free Header h → v {
    ( string_free . h name )
    ( string_free . h value )
}

// Build a one-line "Name: Value\r\n" String. Useful for assembling a
// blob with `string_concat` when the caller wants typed pieces but not
// a full Vec[Header].
@ header_blob_one s name s value → String {
    : i nl ( nurl_str_len name )
    : i vl ( nurl_str_len value )
    : String b ( string_with_cap + + nl vl 4 )
    ( string_push_str b name )
    ( string_push_str b `: ` )
    ( string_push_str b value )
    ( string_push_str b `\r\n` )
    ^ b
}

// Internal: dispatch the perform result onto a NURL ! Response HttpErr.
// `raw` is the i64 returned by `hp_perform` (stdlib/ext/http_pure.nu) —
// 0 means the response struct could not be allocated; non-zero is a heap
// pointer whose `err_kind` slot (slot 1) tells us whether the transport
// succeeded.
//
// Slot layout of the NurlHttpResponse heap struct (stdlib/runtime.c §14,
// native 64-bit), freeable by nurl_http_response_free:
//
//   slot 0  status         i64
//   slot 1  err_kind       i64
//   slot 2  header_count   i64
//   slot 3  headers        *u — NurlHttpHeader[]; each entry is two i64
//                              slots (name, value), 16 bytes on native
//   slot 4  body           *u — owned NUL-terminated body bytes
//   slot 5  body_len       i64
@ __http_dispatch i raw → !Response HttpErr {
    ? == raw 0 { ^ @ !Response HttpErr { F # HttpErr HttpOther } } {}
    : *u rawp # *u raw
    : i ek ( nurl_peek rawp 1 )
    ? != ek 0 {
        ( nurl_http_response_free raw )
        ? == ek 1 { ^ @ !Response HttpErr { F # HttpErr HttpConnect } } {}
        ? == ek 2 { ^ @ !Response HttpErr { F # HttpErr HttpTimeout } } {}
        ? == ek 3 { ^ @ !Response HttpErr { F # HttpErr HttpTls } } {}
        ? == ek 4 { ^ @ !Response HttpErr { F # HttpErr HttpDns } } {}
        ? == ek 5 { ^ @ !Response HttpErr { F # HttpErr HttpInvalidUrl } } {}
        ^ @ !Response HttpErr { F # HttpErr HttpOther }
    } {}
    : s rp # s raw
    : Response r @ Response { rp }
    ^ @ !Response HttpErr { T r }
}

// Core entry point: every other wrapper funnels through here.
@ http_request s method s url s body s headers_blob → !Response HttpErr {
    ^ ( http_request_to method url body headers_blob 0 0 )
}

// Same as http_request but with explicit per-call timeouts in
// milliseconds. The timeout arguments are accepted for source
// compatibility but are not yet honoured by the pure transport (a future
// step will wire socket-level deadlines in).
//
// Dispatch: the pure-NURL HTTP/1.1 client in stdlib/ext/http_pure.nu
// (TLS via stdlib/std/tls.nu for https, raw TCP otherwise).
@ http_request_to s method s url s body s headers_blob i timeout_ms i connect_timeout_ms
→ !Response HttpErr {
    // s-body path: recover length via strlen (text/JSON callers).
    // (timeouts are not yet honoured by the pure transport.)
    : i raw ( hp_perform url method # *u body ( nurl_str_len body ) headers_blob 1 -1 1 `nurl-http/0.1` )
    ^ ( __http_dispatch raw )
}

// Full-control entry point: every transport knob comes from `opt`
// (see HttpOptions). follow_redirects / max_redirects / verify_tls /
// user_agent are honoured by the pure transport; the two timeouts are
// not yet wired in.
@ http_request_with_opts s method s url s body s headers_blob HttpOptions opt
→ !Response HttpErr {
    : s ua_in . opt user_agent
    : s ua ? & != # i ua_in 0 != ( nurl_str_len ua_in ) 0 ua_in `nurl-http/0.1`
    : i raw ( hp_perform url method # *u body ( nurl_str_len body ) headers_blob . opt follow_redirects . opt max_redirects . opt verify_tls ua )
    ^ ( __http_dispatch raw )
}

// Convenience: GET / POST with an explicit HttpOptions.
@ http_get_opts s url HttpOptions opt → !Response HttpErr {
    ^ ( http_request_with_opts `GET` url `` `` opt )
}

@ http_post_opts s url s body s content_type HttpOptions opt → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request_with_opts `POST` url body ( string_data hb ) opt )
    ( string_free hb )
    ^ res
}

// ── GET ─────────────────────────────────────────────────────────────

@ http_get s url → !Response HttpErr {
    ^ ( http_request `GET` url `` `` )
}

@ http_get_with_headers s url s headers_blob → !Response HttpErr {
    ^ ( http_request `GET` url `` headers_blob )
}

// ── POST / PUT / PATCH (body + Content-Type) ───────────────────────
//
// content_type may be `` to skip the Content-Type header (curl picks a
// per-method default). When non-empty, it's prepended to whatever the
// caller put into headers_blob so user-provided headers can still
// override individual fields if desired.

@ __with_ct s ct s headers_blob → String {
    : i ctl ( nurl_str_len ct )
    : i hbl ( nurl_str_len headers_blob )
    : String b ( string_with_cap + + ctl hbl 32 )
    ? > ctl 0 {
        ( string_push_str b `Content-Type: ` )
        ( string_push_str b ct )
        ( string_push_str b `\r\n` )
    } {}
    ? > hbl 0 { ( string_push_str b headers_blob ) } {}
    ^ b
}

@ http_post s url s body s content_type → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request `POST` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

@ http_post_with_headers s url s body s content_type s headers_blob → !Response HttpErr {
    : String hb ( __with_ct content_type headers_blob )
    : !Response HttpErr res ( http_request `POST` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

@ http_put s url s body s content_type → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request `PUT` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

@ http_patch s url s body s content_type → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request `PATCH` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

@ http_delete s url → !Response HttpErr {
    ^ ( http_request `DELETE` url `` `` )
}

// ── Binary-safe body (length-carrying ( Vec u )) ───────────────────
//
// The s-body http_request_* family recovers the body length via
// strlen, so a body with embedded NUL bytes (binary file uploads,
// MessagePack, protobuf, …) truncates at the first NUL. These
// variants carry the body as a length-tracked ( Vec u ) and ship it
// via CURLOPT_COPYPOSTFIELDS + an explicit POSTFIELDSIZE, so the exact
// byte count is sent. `body` is BORROWED — the caller still owns it.
//
// The pure transport sends the exact byte count (Content-Length), so
// embedded NUL bytes survive end to end.
@ http_request_bytes_to s method s url ( Vec u ) body s headers_blob
i timeout_ms i connect_timeout_ms → !Response HttpErr {
    : i raw ( hp_perform url method ( vec_data [u] body ) ( vec_len [u] body ) headers_blob 1 -1 1 `nurl-http/0.1` )
    ^ ( __http_dispatch raw )
}

@ http_request_bytes s method s url ( Vec u ) body s headers_blob → !Response HttpErr {
    ^ ( http_request_bytes_to method url body headers_blob 0 0 )
}

@ http_post_bytes s url ( Vec u ) body s content_type → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request_bytes `POST` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

@ http_put_bytes s url ( Vec u ) body s content_type → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request_bytes `PUT` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

// ── Accessors (borrowed views) — pure NURL over the NurlHttpResponse
//                                 heap struct's i64-slot layout (see
//                                 __http_dispatch above for the map).
//
// Strings returned here point into the response struct's owned storage
// and are valid until `response_free`. The cast pattern is
// `^ # s ( nurl_peek ... )` so the auto-detector sees an i64 binding at
// fn exit and does NOT tag the @-fn's return as owned (avoiding a
// spurious auto-drop of borrowed bytes).

@ http_status Response r → i {
    : s rp . r raw
    : *u rawp # *u rp
    ^ ( nurl_peek rawp 0 )
}

@ http_body_str Response r → s {
    : s rp . r raw
    : *u rawp # *u rp
    : i bp ( nurl_peek rawp 4 )
    ^ ? == bp 0 `` # s bp
}

@ http_body_len Response r → i {
    : s rp . r raw
    : *u rawp # *u rp
    ^ ( nurl_peek rawp 5 )
}

// Owned, length-accurate binary copy of the response body. Unlike
// http_body_str (which stops at the first NUL via strlen on the carrier),
// this preserves embedded NUL bytes — required for binary downloads
// (package tarballs, images, compressed payloads). Caller frees with
// `( vec_free [u] … )`.
@ http_body_bytes Response r → ( Vec u ) {
    : s rp . r raw
    : *u rawp # *u rp
    : i bp ( nurl_peek rawp 4 )
    : i blen ( nurl_peek rawp 5 )
    : ( Vec u ) out ( vec_with_cap [u] ? > blen 0 blen 1 )
    ? & != bp 0 > blen 0 {
        : *u src # *u bp
        : ~ i k 0
        ~ < k blen {
            ( vec_push [u] out . src k )
            = k + k 1
        }
    } {}
    ^ out
}

@ http_header_count Response r → i {
    : s rp . r raw
    : *u rawp # *u rp
    ^ ( nurl_peek rawp 2 )
}

@ http_header_name Response r i idx → s {
    : s rp . r raw
    : *u rawp # *u rp
    : i hc ( nurl_peek rawp 2 )
    ? || < idx 0 >= idx hc { ^ `` } {}
    : i ap ( nurl_peek rawp 3 )
    ? == ap 0 { ^ `` } {}
    : *u arr # *u ap
    : i name_slot * idx 2
    : i np ( nurl_peek arr name_slot )
    ^ ? == np 0 `` # s np
}

@ http_header_value Response r i idx → s {
    : s rp . r raw
    : *u rawp # *u rp
    : i hc ( nurl_peek rawp 2 )
    ? || < idx 0 >= idx hc { ^ `` } {}
    : i ap ( nurl_peek rawp 3 )
    ? == ap 0 { ^ `` } {}
    : *u arr # *u ap
    : i name_slot * idx 2
    : i value_slot + name_slot 1
    : i vp ( nurl_peek arr value_slot )
    ^ ? == vp 0 `` # s vp
}

@ response_free Response r → v {
    : s rp . r raw
    : i raw # i rp
    ( nurl_http_response_free raw )
}

// Render a HttpErr variant name. Useful for diagnostic messages without
// a full match cascade at every call site.
@ http_err_name HttpErr e → s {
    ^ ?? e {
        HttpConnect → `HttpConnect`
        HttpTimeout → `HttpTimeout`
        HttpTls → `HttpTls`
        HttpDns → `HttpDns`
        HttpInvalidUrl → `HttpInvalidUrl`
        HttpOther → `HttpOther`
    }
}

// ── HTTP streaming (pull-based) ─────────────────────────────────────
//
// For SSE / chunked responses where the body arrives over time and the
// caller wants to react to each chunk before the request completes.
// Backed by libcurl's multi handle in `runtime.c §14b`; WinHTTP and
// WASI builds return `HttpOther` on open.
//
//   ( http_stream_open_to s method s url s body s headers_blob
//                         i timeout_ms i connect_timeout_ms )
//                                                  → ! HttpStream HttpErr
//   ( http_stream_open    s method s url s body s headers_blob )
//                                                  → ! HttpStream HttpErr
//   ( http_stream_next    HttpStream s )           → ? String
//                       owned chunk; None = EOF or error (probe via
//                       http_stream_err / http_stream_status). Each
//                       chunk is whatever libcurl flushed since the
//                       last call — NOT a single SSE frame. Compose
//                       with `SseDecoder` (below) for event-aligned
//                       reads.
//   ( http_stream_status  HttpStream s )           → i
//                       Final HTTP status, valid after http_stream_next
//                       has returned None.
//   ( http_stream_err     HttpStream s )           → ? HttpErr
//                       None = transfer succeeded; Some(e) = failure.
//   ( http_stream_close   HttpStream s )           → v
//                       MUST be called exactly once per opened stream.
//
// Memory model:
//   * Each `http_stream_next` chunk is a freshly-owned `String` —
//     callers are responsible for freeing them. Returning a Vec[u]
//     instead would double the per-chunk allocation cost; SSE is text
//     so String is the right type.
//   * The HttpStream handle owns the libcurl multi+easy pair and a
//     small accumulator buffer. `http_stream_close` cascades to all of
//     them; do not call after close.
//   * Inputs (method/url/body/headers_blob) are BORROWED — a snapshot
//     is taken inside libcurl, so the caller may free them right away.

: HttpStream { i raw }

// Shared open-result dispatch for both the s-body and ( Vec u )-body
// stream openers. `raw` is a *HttpStreamState (as i64); probe err_kind in
// case open recorded a transport failure (e.g. malformed URL / connect).
@ __http_stream_dispatch_open i raw → !HttpStream HttpErr {
    ? == raw 0 {
        ^ @ !HttpStream HttpErr { F # HttpErr HttpOther }
    } {}
    : i ek ( hp_stream_err_kind # *HttpStreamState raw )
    ? != ek 0 {
        ( hp_stream_close # *HttpStreamState raw )
        ? == ek 1 { ^ @ !HttpStream HttpErr { F # HttpErr HttpConnect } } {}
        ? == ek 2 { ^ @ !HttpStream HttpErr { F # HttpErr HttpTimeout } } {}
        ? == ek 3 { ^ @ !HttpStream HttpErr { F # HttpErr HttpTls } } {}
        ? == ek 4 { ^ @ !HttpStream HttpErr { F # HttpErr HttpDns } } {}
        ? == ek 5 { ^ @ !HttpStream HttpErr { F # HttpErr HttpInvalidUrl } } {}
        ^ @ !HttpStream HttpErr { F # HttpErr HttpOther }
    } {}
    ^ @ !HttpStream HttpErr { T @ HttpStream { raw } }
}

@ http_stream_open_to s method s url s body s headers_blob
i timeout_ms i connect_timeout_ms
→ !HttpStream HttpErr {
    : *HttpStreamState st ( hp_stream_open method url # *u body ( nurl_str_len body ) headers_blob 1 -1 1 `nurl-http/0.1` )
    ^ ( __http_stream_dispatch_open # i st )
}

// Binary-safe streaming open: the body is a length-carrying ( Vec u ),
// so embedded NUL bytes survive. The request bytes are copied during
// open, so `body` may be freed as soon as this returns.
@ http_stream_open_bytes_to s method s url ( Vec u ) body s headers_blob
i timeout_ms i connect_timeout_ms
→ !HttpStream HttpErr {
    : *HttpStreamState st ( hp_stream_open method url ( vec_data [u] body ) ( vec_len [u] body ) headers_blob 1 -1 1 `nurl-http/0.1` )
    ^ ( __http_stream_dispatch_open # i st )
}

@ http_stream_open s method s url s body s headers_blob
→ !HttpStream HttpErr {
    ^ ( http_stream_open_to method url body headers_blob 0 0 )
}

@ http_stream_next HttpStream st → ?String {
    ^ ( hp_stream_next_str # *HttpStreamState . st raw )
}

// Binary-safe body-chunk pull — embedded NUL bytes survive (unlike the
// `?String` carrier of http_stream_next). None at end-of-stream or on
// error (consult http_stream_err to tell them apart).
@ http_stream_next_bytes HttpStream st → ?( Vec u ) {
    ^ ( hp_stream_next_bytes # *HttpStreamState . st raw )
}

@ http_stream_status HttpStream st → i {
    ^ ( hp_stream_status # *HttpStreamState . st raw )
}

@ http_stream_err HttpStream st → ?HttpErr {
    : i ek ( hp_stream_err_kind # *HttpStreamState . st raw )
    ? == ek 0 { ^ @ ?HttpErr { F # HttpErr HttpOther } } {}
    ? == ek 1 { ^ @ ?HttpErr { T # HttpErr HttpConnect } } {}
    ? == ek 2 { ^ @ ?HttpErr { T # HttpErr HttpTimeout } } {}
    ? == ek 3 { ^ @ ?HttpErr { T # HttpErr HttpTls } } {}
    ? == ek 4 { ^ @ ?HttpErr { T # HttpErr HttpDns } } {}
    ? == ek 5 { ^ @ ?HttpErr { T # HttpErr HttpInvalidUrl } } {}
    ^ @ ?HttpErr { T # HttpErr HttpOther }
}

@ http_stream_close HttpStream st → v {
    ( hp_stream_close # *HttpStreamState . st raw )
}

// Pump the multi handle until the upstream response headers are
// received OR the transfer terminates. After this returns:
//   * `http_stream_status` carries the upstream status code (0 if the
//     transfer aborted before the status line was received).
//   * `http_stream_header_count` / `_name` / `_value` are populated.
//   * `http_stream_next` may now be called to pull body chunks.
//
// Returns the upstream status code (0 = no status, e.g. DNS / connect
// failure — call `http_stream_err` to learn why). 1xx informational
// responses are skipped automatically; the value here always reflects
// the FINAL response.
//
// Used by reverse-proxy code (`stdlib/ext/http_proxy.nu`) to learn the
// upstream status + headers before deciding what to write back to the
// downstream client.
@ http_stream_pump_headers HttpStream st → i {
    ^ ( hp_stream_pump_headers # *HttpStreamState . st raw )
}

@ http_stream_header_count HttpStream st → i {
    ^ ( hp_stream_header_count # *HttpStreamState . st raw )
}

// BORROWED — lifetime tied to the HttpStream handle. Free not required
// (and not allowed); copy with `string_from` if a long-lived String is
// needed.
@ http_stream_header_name HttpStream st i idx → s {
    ^ ( hp_stream_header_name # *HttpStreamState . st raw idx )
}

@ http_stream_header_value HttpStream st i idx → s {
    ^ ( hp_stream_header_value # *HttpStreamState . st raw idx )
}

// ── SSE parser (Server-Sent Events / W3C, Anthropic streaming) ──────
//
// Stateless helpers — the caller owns an accumulator (typically a
// `~ String acc`), feeds each `http_stream_next` chunk into it via
// `string_push_str`, and pops complete events with the loop below.
// We do not bundle the accumulator into a struct because NURL has no
// surface syntax for replacing a typed struct field — keeping the
// accumulator as a local mutable binding (`= acc <fresh String>`) is
// the idiomatic shape, and it sidesteps the issue cleanly.
//
// Frame format: lines separated by `\n`, frame terminated by an empty
// line (i.e. `\n\n`). Recognised fields: `event`, `data`, `id`. Lines
// beginning with `:` are comments per the spec (Anthropic emits them
// as keepalives). Multi-line `data:` lines are joined with `\n`.
//
// Typical loop:
//
//   : ~ String acc ( string_with_cap 1024 )
//   ~ T {
//     : ? String chopt ( http_stream_next st )
//     ?? chopt {
//       T ch → {
//         ( string_push_str acc ( string_data ch ) )
//         ( string_free ch )
//         ~ T {
//           : i fend ( sse_frame_end ( string_data acc ) ( string_len acc ) )
//           ? < fend 0 { ! T } {}
//           : SseEvent ev ( sse_parse_frame ( string_data acc ) fend )
//           // … use ev …
//           ( sse_event_free ev )
//           : i total ( string_len acc )
//           : i drop + fend 2
//           : String rest ( string_substr acc drop - total drop )
//           ( string_free acc )
//           = acc rest
//         }
//       }
//       F → { ! T }
//     }
//   }
//   ( string_free acc )

: SseEvent { String name String data String id }

// Copy bytes [from, from+n) of a raw `s` into a fresh owned String.
// Used internally by the SSE parser to materialise frame field tokens.
@ __sse_substr s p i from i n → String {
    : String out ( string_with_cap n )
    : ~ i k 0
    ~ < k n {
        ( string_push_char out ( nurl_str_get p + from k ) )
        = k + k 1
    }
    ^ out
}

@ sse_event_free SseEvent e → v {
    ( string_free . e name )
    ( string_free . e data )
    ( string_free . e id )
}

// Find the first `\n\n` separator inside the accumulator buffer. Returns
// the byte offset of the FIRST `\n` of the pair (so the frame is
// `acc[0 .. offset)` and the next frame starts at `offset + 2`). Returns
// -1 when no complete frame is buffered yet.
@ sse_frame_end s acc i acc_len → i {
    : ~ i i 0
    ~ < i - acc_len 1 {
        ? & == ( nurl_str_get acc i ) 10 == ( nurl_str_get acc + i 1 ) 10 {
            ^ i
        } {}
        = i + i 1
    }
    ^ -1
}

// Parse a complete frame (the bytes up to but excluding the `\n\n`
// separator). Returns an owned SseEvent — empty fields are valid (e.g.
// no `event:` line → name = ""). Caller frees with `sse_event_free`.
@ sse_parse_frame s frame i frame_len → SseEvent {
    : ~ String name ( string_new )
    : String data ( string_new )
    : ~ String id ( string_new )
    : ~ b first_data_line T

    : ~ i ls 0
    : ~ i i 0
    ~ <= i frame_len {
        : i c ? < i frame_len ( nurl_str_get frame i ) 10
        ? == c 10 {
            : i llen - i ls
            ? > llen 0 {
                : i firstc ( nurl_str_get frame ls )
                ? == firstc 58 {
                    // Comment line — skip.
                } {
                    // Find the colon delimiter inside [ls, i).
                    : ~ i ci ls
                    : ~ b found F
                    ~ & ! found < ci i {
                        ? == ( nurl_str_get frame ci ) 58 { = found T } {
                            = ci + ci 1
                        }
                    }
                    : i fld_len - ci ls
                    : ~ i vstart ? found + ci 1 i
                    ? & found < vstart i {
                        ? == ( nurl_str_get frame vstart ) 32 { = vstart + vstart 1 } {}
                    } {}
                    : i vlen ? found - i vstart 0
                    : String fld ( __sse_substr frame ls fld_len )
                    : String val ( __sse_substr frame vstart vlen )

                    : s fp ( string_data fld )
                    ? != ( nurl_str_eq fp `event` ) 0 {
                        ( string_free name )
                        = name ( string_from ( string_data val ) )
                    } {
                        ? != ( nurl_str_eq fp `data` ) 0 {
                            ? first_data_line {
                                = first_data_line F
                            } {
                                ( string_push_str data `\n` )
                            }
                            ( string_push_str data ( string_data val ) )
                        } {
                            ? != ( nurl_str_eq fp `id` ) 0 {
                                ( string_free id )
                                = id ( string_from ( string_data val ) )
                            } {}
                        }
                    }
                    ( string_free fld )
                    ( string_free val )
                }
            } {}
            = ls + i 1
        } {}
        = i + i 1
    }
    ^ @ SseEvent { name data id }
}
