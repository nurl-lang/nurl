// stdlib/ext/http_proxy.nu — Reverse-proxy / streaming pass-through
// (Phase 9 leftover of HTTP_SERVER_PLAN.md). Combines the HTTP client
// (`stdlib/ext/http.nu` + libcurl multi streaming in `runtime.c §14b`)
// with the chunked response writer (`stdlib/ext/http_response.nu`) so
// a NURL program can sit in front of any upstream HTTP origin —
// typically an AI provider (Anthropic / OpenAI / Google / local
// Ollama) — and stream responses back to the client without buffering
// full payloads in memory.
//
// `proxy_stream_to_conn` opens an HTTP stream against upstream, pumps
// headers, then writes a `Transfer-Encoding: chunked` response straight
// to a TcpConn, flushing each upstream chunk as it arrives. Used for
// SSE / AI token streams where the value of the proxy is delivering
// bytes to the client as soon as upstream emits them. `proxy_serve_run`
// runs a dedicated accept loop that streams every request to a fixed
// upstream base URL.
//
// A buffered (`! HttpResponse HttpErr`) API is not provided in v1 —
// streaming is the only mode that matters for AI gateways and the
// streaming path is plenty for the proxy use case. The multi-field
// Result Ok-arm heap-boxing fix shipped 2026-05-14 has unblocked this
// shape, so adding a buffered variant later is a clean follow-up if
// a real consumer asks for it.
//
// API (this revision):
//
//   ( proxy_default_opts )                                  → ProxyOpts
//   ( proxy_err_name ProxyErr e )                           → s
//
//   ( proxy_stream_to_conn      TcpConn conn HttpRequest req s upstream_url )                → ! v ProxyErr
//   ( proxy_stream_to_conn_with TcpConn conn HttpRequest req s upstream_url ProxyOpts opts ) → ! v ProxyErr
//
//   ( proxy_serve_run      TcpListener listener s upstream_base )                → ! v NetErr
//   ( proxy_serve_run_with TcpListener listener s upstream_base ProxyOpts opts ) → ! v NetErr
//
// Memory model:
//
//   * `proxy_stream_to_conn` BORROWS `conn` and `req`. Writes wire
//     bytes directly to `conn`; on a successful return the response
//     has been fully delivered (chunked terminator written). The
//     caller still owns `conn` and is responsible for closing /
//     keep-alive accounting. The handler does NOT consume the
//     request — `request_free` is the caller's job.
//   * `proxy_serve_run` runs forever until the listener is closed
//     (e.g. from `signal_install_shutdown`). It owns the inner
//     accept→stream loop including request parsing.
//
// Header policy:
//
//   * **Request → upstream:** RFC 7230 §6.1 hop-by-hop headers are
//     dropped (Connection, Keep-Alive, Proxy-Authenticate,
//     Proxy-Authorization, TE, Trailer, Transfer-Encoding, Upgrade).
//     `Host` is dropped (libcurl rebuilds it from the upstream URL)
//     unless `preserve_host_header` is set. `Content-Length` is
//     dropped (libcurl recomputes from the body).
//   * **Upstream → client:** hop-by-hop headers are dropped.
//     `Content-Length` is dropped because we re-encode as chunked.
//     `Content-Encoding` is dropped because libcurl auto-decompresses
//     the upstream body (we set `Accept-Encoding: ""` to opt in to
//     transparent decoding) — keeping the header would lie to the
//     client.
//
// Limitations (v1):
//
//   * Request body is shipped via `CURLOPT_POSTFIELDS` which uses
//     `strlen(body)` on the C runtime side — embedded NUL bytes in
//     the request body are truncated. JSON / text payloads work as
//     expected; binary file uploads through the proxy are not
//     guaranteed lossless until a length-aware POSTFIELDS path lands.
//   * Streaming-mode response body chunks travel through a NUL-
//     terminated `char*` carrier in `nurl_http_stream_next`; binary
//     responses with embedded NULs would be truncated. SSE / JSON /
//     text (i.e. every LLM output today) is fine.
//   * `proxy_serve_run` accepts every connection unconditionally —
//     no auth, no rate limit. For those, build the loop yourself
//     with `tcp_accept` + your auth check + `proxy_stream_to_conn`.
//   * No Trailer-header passthrough.
//   * No HTTP/1.1 `Expect: 100-continue` upstream signalling.

$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

// ── ProxyOpts ─────────────────────────────────────────────────────────

: ProxyOpts {
    i timeout_ms
    i connect_timeout_ms
    b strip_hop_by_hop
    b preserve_host_header
    b strip_content_encoding
    b strip_content_length
}

// 60 s total / 10 s connect — LLM streaming endpoints can take a
// minute or more so we go higher than the http.nu default. The two
// strip flags default ON because they match the chunked-response
// re-encoding we always apply.
@ proxy_default_opts → ProxyOpts {
    ^ @ ProxyOpts { 60000 10000 T F T T }
}

// ── ProxyErr ──────────────────────────────────────────────────────────
//
// ProxyErr distinguishes the failure mode so callers can decide whether
// to retry (network blip → ProxyUpstream), give up (bad client →
// ProxyClientWrite), or surface a 500 (catch-all → ProxyOther).

: | ProxyErr {
    ProxyUpstream
    ProxyClientWrite
    ProxyOther
}

@ proxy_err_name ProxyErr e → s {
    ^ ?? e {
        ProxyUpstream → `ProxyUpstream`
        ProxyClientWrite → `ProxyClientWrite`
        ProxyOther → `ProxyOther`
    }
}

// ── Hop-by-hop classification ─────────────────────────────────────────
//
// `name_lc` is a lowered NUL-terminated raw-`s`; the eight tokens come
// straight from RFC 7230 §6.1. Compared with the existing `__is_hop_by_hop`
// hand-rolled set in middleware code (none today), this central helper
// makes the policy auditable in one place.
@ __is_hop_by_hop s name_lc → b {
    ? != 0 ( nurl_str_eq name_lc `connection` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name_lc `keep-alive` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name_lc `proxy-authenticate` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name_lc `proxy-authorization` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name_lc `te` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name_lc `trailer` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name_lc `transfer-encoding` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name_lc `upgrade` ) { ^ T } {}
    ^ F
}

// Build the upstream URL by joining `base` with `req.path` + `?` +
// `req.query`. If `base` ends with `/` AND `req.path` starts with `/`
// we strip one to avoid `https://api.example.com//v1/foo`.
@ __build_upstream_url s base HttpRequest req → String {
    : i bn ( nurl_str_len base )
    : i pn ( string_len . req path )
    : i qn ( string_len . req query )
    : String url ( string_with_cap + + + bn pn qn 4 )
    ( string_push_str url base )
    : ~ b base_slash F
    ? > bn 0 { ? == ( nurl_str_get base - bn 1 ) 47 { = base_slash T } {} } {}
    : ~ b path_slash F
    ? > pn 0 { ? == ( string_get . req path 0 ) 47 { = path_slash T } {} } {}
    : ~ i path_start 0
    ? & base_slash path_slash { = path_start 1 } {}
    ? > pn path_start {
        : ~ i k path_start
        ~ < k pn {
            ( string_push_char url ( string_get . req path k ) )
            = k + k 1
        }
    } {}
    ? > qn 0 {
        ( string_push_str url `?` )
        ( string_push_str url ( string_data . req query ) )
    } {}
    ^ url
}

// Build a libcurl-style headers blob ("Name: Value\r\n…") from the
// request's headers, applying the request-side filter rules described
// in the module-header policy block. Caller frees the returned String.
@ __build_request_headers_blob HttpRequest req ProxyOpts opts → String {
    : String blob ( string_new )
    : i n ( vec_len [Header] . req headers )
    : *Header data ( vec_data [Header] . req headers )
    : ~ i k 0
    ~ < k n {
        : Header h . data k
        : String name_lc ( string_to_lower . h name )
        : s nm_lc ( string_data name_lc )
        : ~ b drop F
        ? & . opts strip_hop_by_hop ( __is_hop_by_hop nm_lc ) { = drop T } {}
        ? & ! . opts preserve_host_header != 0 ( nurl_str_eq nm_lc `host` ) {
            = drop T
        } {}
        ? != 0 ( nurl_str_eq nm_lc `content-length` ) { = drop T } {}
        ? ! drop {
            ( string_push_str blob ( string_data . h name ) )
            ( string_push_str blob `: ` )
            ( string_push_str blob ( string_data . h value ) )
            ( string_push_str blob `\r\n` )
        } {}
        ( string_free name_lc )
        = k + k 1
    }
    ^ blob
}

// Decide whether an upstream-response header should ride back to the
// downstream client. Inputs are NUL-terminated raw-`s` (the runtime's
// view) so we lower into a temporary String, compare, and free it.
@ __response_header_dropped s name ProxyOpts opts → b {
    : i nl ( nurl_str_len name )
    ? <= nl 0 { ^ T } {}
    : String name_s ( string_from name )
    : String lc ( string_to_lower name_s )
    : s lcr ( string_data lc )
    : ~ b drop F
    ? & . opts strip_hop_by_hop ( __is_hop_by_hop lcr ) { = drop T } {}
    ? & . opts strip_content_length != 0 ( nurl_str_eq lcr `content-length` ) {
        = drop T
    } {}
    ? & . opts strip_content_encoding != 0 ( nurl_str_eq lcr `content-encoding` ) {
        = drop T
    } {}
    ( string_free lc )
    ( string_free name_s )
    ^ drop
}

// ── Streaming proxy ───────────────────────────────────────────────────
//
// Writes a `Transfer-Encoding: chunked` response straight to `conn`.
// Mirrors libcurl's incremental delivery — every upstream chunk that
// the multi handle yields becomes one chunk on the wire to the
// downstream client. This is the path AI-gateway operators want for
// SSE / token-streaming responses; latency between upstream byte
// arrival and downstream byte delivery is bounded by the libcurl
// pump cycle (~one perform() call per chunk).
//
// On error: the conn may be in a partially-written state. The caller
// MUST close `conn` after a ProxyErr. For ProxyClientWrite the chunk
// stream was already begun, so the wire is unrecoverable; for
// ProxyUpstream we may have written nothing OR the status line + some
// headers — either way close-and-move-on is the right disposition.

@ proxy_stream_to_conn TcpConn conn HttpRequest req s upstream_url → !v ProxyErr {
    ^ ( proxy_stream_to_conn_with conn req upstream_url ( proxy_default_opts ) )
}

@ proxy_stream_to_conn_with TcpConn conn HttpRequest req s upstream_url ProxyOpts opts → !v ProxyErr {
    : String headers_blob ( __build_request_headers_blob req opts )
    : i bn ( vec_len [u] . req body )
    : *u bdata ( vec_data [u] . req body )
    : String body_s ( string_from_bytes bdata bn )

    : !HttpStream HttpErr or ( http_stream_open_to
    ( string_data . req method )
    upstream_url
    ( string_data body_s )
    ( string_data headers_blob )
    . opts timeout_ms
    . opts connect_timeout_ms )

    ( string_free headers_blob )
    ( string_free body_s )

    ?? or {
        T st → {
            : i status ( http_stream_pump_headers st )
            ? <= status 0 {
                ( http_stream_close st )
                ^ @ !v ProxyErr { F # ProxyErr ProxyUpstream }
            } {}

            // Build the header set we forward to the client.
            : ( Vec Header ) hs ( vec_new [Header] )
            : i hcount ( http_stream_header_count st )
            : ~ i k 0
            ~ < k hcount {
                : s name ( http_stream_header_name st k )
                : s value ( http_stream_header_value st k )
                ? ! ( __response_header_dropped name opts ) {
                    ( vec_push [Header] hs ( header_new name value ) )
                } {}
                = k + k 1
            }

            // Status + headers + chunked TE in one write.
            : !v NetErr beg ( response_begin_chunked conn status hs )
            ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
            ?? beg {
                T _ → {}
                F _ → {
                    ( http_stream_close st )
                    ^ @ !v ProxyErr { F # ProxyErr ProxyClientWrite }
                }
            }

            // Pull body chunks until EOF / upstream error.
            : ~ b done F
            : ~ i status_local 0  // 0 = ok, 1 = client_write, 2 = upstream
            ~ ! done {
                : ?String chunk_opt ( http_stream_next st )
                ?? chunk_opt {
                    T chunk → {
                        : i clen ( string_len chunk )
                        ? > clen 0 {
                            : ( Vec u ) cb ( vec_with_cap [u] clen )
                            ( bytes_extend_str cb ( string_data chunk ) )
                            : !v NetErr wr ( response_write_chunk conn cb )
                            ( vec_free [u] cb )
                            ?? wr {
                                T _ → {}
                                F _ → { = status_local 1 = done T }
                            }
                        } {}
                        ( string_free chunk )
                    }
                    F _ → { = done T }
                }
            }

            // Decide upstream-success vs. upstream-error from the stream's
            // err_kind (set when the multi handle reported done).
            ? == status_local 0 {
                : ?HttpErr eo ( http_stream_err st )
                ?? eo {
                    T _ → { = status_local 2 }
                    F _ → {}
                }
            } {}

            ( http_stream_close st )

            ? == status_local 1 {
                ^ @ !v ProxyErr { F # ProxyErr ProxyClientWrite }
            } {}
            ? == status_local 2 {
                // Upstream broke mid-stream. We've already begun chunked, so
                // the wire is unrecoverable — terminate the chunk stream and
                // surface the error so the caller knows to close.
                : !v NetErr _end ( response_end_chunked conn )
                ?? _end { T _ → {} F _ → {} }
                ^ @ !v ProxyErr { F # ProxyErr ProxyUpstream }
            } {}

            : !v NetErr endr ( response_end_chunked conn )
            ?? endr {
                T _ → ^ @ !v ProxyErr { T 0 }
                F _ → ^ @ !v ProxyErr { F # ProxyErr ProxyClientWrite }
            }
        }
        F _ → ^ @ !v ProxyErr { F # ProxyErr ProxyUpstream }
    }
}

// ── proxy_serve_run — dedicated streaming proxy server ────────────────
//
// Accept loop: every incoming request → streamed to upstream_base.
// No auth, no routing — that's what custom loops are for. Returns
// when the listener is closed (typically via signal_install_shutdown).

@ proxy_serve_run TcpListener listener s upstream_base → !v NetErr {
    ^ ( proxy_serve_run_with listener upstream_base ( proxy_default_opts ) )
}

@ proxy_serve_run_with TcpListener listener s upstream_base ProxyOpts opts → !v NetErr {
    : ~ b done F
    : ~ b had_err F
    ~ ! done {
        : !TcpConn NetErr ar ( tcp_accept listener )
        ?? ar {
            T conn → {
                // Match http_server's defaults: 30 s recv idle so a slow
                // client can't pin us forever.
                ( tcp_set_timeout conn 30000 )
                // One-shot connection (no keep-alive on this path) but
                // __read_request_head + __finish_body still take a carry
                // Vec[u] — pipelining-correct head/body framing applies
                // regardless of whether we serve more than one request.
                // Limits: proxy uses the stdlib defaults; per-request
                // total timeout isn't enforced here (proxy is dominated
                // by upstream latency, which `ProxyOpts.timeout_ms`
                // already bounds).
                : ( Vec u ) carry ( vec_with_cap [u] 4096 )
                : HttpLimits lim ( http_default_limits )
                : ! ParsedHeadOk HttpReqErr ph ( __read_request_head conn carry lim )
                ?? ph {
                    T pho → {
                        : HttpRequest req . pho head
                        : b body_ok ( __finish_body conn req carry . lim body_default_max )
                        ? body_ok {
                            : String url ( __build_upstream_url upstream_base req )
                            : !v ProxyErr pr ( proxy_stream_to_conn_with conn req
                            ( string_data url ) opts )
                            ( string_free url )
                            ?? pr {
                                T _ → {}
                                F _ → {}
                            }
                        } {
                            : HttpResponse er ( response_text 400 `malformed body\n` )
                            ( response_set_header er `Connection` `close` )
                            : ( Vec u ) wire ( response_serialize er )
                            : !v NetErr _wr ( tcp_write_all conn wire )
                            ?? _wr { T _ → {} F _ → {} }
                            ( vec_free [u] wire )
                            ( http_response_free er )
                        }
                        ( request_free req )
                    }
                    F e → {
                        // Don't silently drop a syntactically-bad request — the
                        // 4xx response helps developers debugging through curl.
                        : s nm ( http_req_err_name e )
                        ? != 0 ( nurl_str_eq nm `HttpReqIo` ) {} {
                            : HttpResponse er ( __parse_err_response e )
                            ( response_set_header er `Connection` `close` )
                            : ( Vec u ) wire ( response_serialize er )
                            : !v NetErr _wr ( tcp_write_all conn wire )
                            ?? _wr { T _ → {} F _ → {} }
                            ( vec_free [u] wire )
                            ( http_response_free er )
                        }
                    }
                }
                ( vec_free [u] carry )
                ( tcp_close_conn conn )
            }
            F e → {
                : s nm ( net_err_name e )
                ? | != 0 ( nurl_str_eq nm `NetClosed` ) != 0 ( nurl_str_eq nm `NetAccept` ) {
                    = done T
                } {
                    = had_err T
                    = done T
                }
            }
        }
    }
    ? had_err {
        : !TcpConn NetErr ar2 ( tcp_accept listener )
        ?? ar2 {
            T c → { ( tcp_close_conn c ) }
            F e → ^ @ !v NetErr { F e }
        }
    } {}
    ^ @ !v NetErr { T 0 }
}
