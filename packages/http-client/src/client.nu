// http-client/client.nu — the ergonomic HttpClient facade over the
// stdlib client stack.
//
// The stdlib ships a complete client toolkit — pure-NURL TLS 1.3 (with
// X25519MLKEM768 hybrid key exchange and ML-DSA certificate chains), an
// HTTP/1.1 keep-alive client (http_pure.nu), a multiplexed HTTP/2 client
// (http2_client.nu), an RFC 6265 cookie jar (cookies.nu), and gzip /
// deflate (compress.nu). What every program re-invents is the glue that
// wires them into one thing: pick the protocol the server actually
// offers, pool the connection to reuse it, carry cookies, follow
// redirects, decode the body.
//
// `HttpClient` collapses that into one object:
//
//     : *HttpClient c ( http_client_new )
//     ?? ( http_client_get c `https://example.org/` ) {
//         T r → { ( nurl_print_int . r status ) ( http_response_free r ) }
//         F e → { ( nurl_eprintln ( http_client_err_name e ) ) }
//     }
//     ( http_client_free c )
//
// Protocol selection is automatic and needs nothing configured: an
// https origin is dialled with ALPN "h2 http/1.1", and whichever the
// server picks is what the client speaks — HTTP/2 multiplexed over one
// connection, or HTTP/1.1 with keep-alive. The negotiated protocol and
// whether the key exchange was post-quantum are readable after each
// request (`http_client_last_proto` / `http_client_last_pq`).
//
// Memory model: `http_client_new` returns a heap `*HttpClient`; free it
// with `http_client_free`, which closes every pooled connection. A
// returned `HttpResponse` is owned by the caller (`http_response_free`).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/url.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_pure.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_client.nu`
$ `stdlib/ext/cookies.nu`
$ `stdlib/ext/compress.nu`

// ── Errors ────────────────────────────────────────────────────────────
//
// One error type for the whole client — the h1 transport, the h2
// transport and TLS all fold into these.
: | HttpClientErr {
    HcConnect  // TCP / TLS connect failed
    HcTimeout  // a read or write passed the deadline
    HcTls  // TLS handshake or certificate verification failed
    HcDns  // hostname did not resolve
    HcInvalidUrl  // malformed URL or a scheme other than http/https
    HcProtocol  // the peer broke framing (bad h2/h1 response)
    HcTooManyRedirects  // the redirect chain passed max_redirects
    HcTooLarge  // the response body passed the size cap
    HcDecode  // a Content-Encoding body would not decompress
    HcOther
}

// Case-insensitive ASCII equality of a header name against a lowercase
// literal — the client's own copy so it needs nothing file-private from
// http_request.nu.
@ _hc_eq_ci s a s b → b {
    : i la ( nurl_str_len a )
    ? != la ( nurl_str_len b ) { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k la {
        : ~ i ca ( nurl_str_get a k )
        : ~ i cb ( nurl_str_get b k )
        ? & >= ca 65 <= ca 90 { = ca + ca 32 } {}
        ? & >= cb 65 <= cb 90 { = cb + cb 32 } {}
        ? != ca cb { = ok F } {}
        = k + k 1
    }
    ^ ok
}

@ http_client_err_name HttpClientErr e → s {
    ^ ?? e {
        HcConnect → `HcConnect`
        HcTimeout → `HcTimeout`
        HcTls → `HcTls`
        HcDns → `HcDns`
        HcInvalidUrl → `HcInvalidUrl`
        HcProtocol → `HcProtocol`
        HcTooManyRedirects → `HcTooManyRedirects`
        HcTooLarge → `HcTooLarge`
        HcDecode → `HcDecode`
        HcOther → `HcOther`
    }
}

// ── Pooled origin ─────────────────────────────────────────────────────
//
// One live connection per (scheme, host, port). `proto` records what the
// origin negotiated: 0 nothing yet, 1 HTTP/1.1, 2 HTTP/2. For h2 the
// pooled connection is the multiplexed H2Client; for h1 it is one idle
// keep-alive HttpConn, present only while `has_h1` is 1.
: HcOrigin {
    String key  // "scheme://host:port"
    String host
    i port
    i is_https
    i proto
    i has_h2 H2Client h2
    i has_h1 HttpConn h1
    i pq  // 1 = the TLS key exchange for this origin was post-quantum
}

// ── Client ────────────────────────────────────────────────────────────
: HttpClient {
    CookieJar jar
    ( Vec i ) origins  // *HcOrigin boxed, so the structs have stable identity
    i verify  // verify TLS chains (1) or not (0)
    i follow  // follow redirects (1) or return the 3xx (0)
    i max_redirects
    i timeout_ms  // per read/write deadline; 0 = none
    i decompress  // request + decode gzip/deflate (1) or leave bodies raw (0)
    i body_max  // response body cap in bytes; 0 = unlimited
    String ua
    // Evidence from the most recent request.
    i last_proto  // 1 h1, 2 h2, 0 none yet
    i last_pq  // 1 = post-quantum key exchange
}

@ http_client_new → *HttpClient {
    : *HttpClient c # *HttpClient ( nurl_malloc Z HttpClient )
    = . c jar ( cookie_jar_new )
    = . c origins ( vec_new [i] )
    = . c verify 1
    = . c follow 1
    = . c max_redirects 10
    = . c timeout_ms 30000
    = . c decompress 1
    = . c body_max 0
    = . c ua ( string_from `nurl-http-client/0.1` )
    = . c last_proto 0
    = . c last_pq 0
    ^ c
}

// ── Configuration (chainable-by-mutation) ─────────────────────────────

// Skip TLS certificate / hostname verification. For pinned, self-signed
// or test servers only — an unverified connection authenticates nothing.
@ http_client_set_verify * HttpClient c b on → v { = . c verify ? on 1 0 }

// Follow 3xx redirects (default) or hand the 3xx response back.
@ http_client_set_follow * HttpClient c b on → v { = . c follow ? on 1 0 }

@ http_client_set_max_redirects * HttpClient c i n → v { = . c max_redirects n }

// Per read/write deadline in milliseconds (0 = none). A stalled server
// answers HcTimeout instead of hanging.
@ http_client_set_timeout * HttpClient c i ms → v { = . c timeout_ms ms }

// Offer and decode gzip/deflate bodies (default) or leave the body as
// the wire carried it (the caller then owns Content-Encoding).
@ http_client_set_decompress * HttpClient c b on → v { = . c decompress ? on 1 0 }

// Cap the (decoded) response body; a larger body answers HcTooLarge.
@ http_client_set_body_max * HttpClient c i n → v { = . c body_max n }

@ http_client_set_user_agent * HttpClient c s ua → v {
    ( string_free . c ua )
    = . c ua ( string_from ua )
}

// The protocol / key-exchange facts of the most recent request.
@ http_client_last_proto * HttpClient c → i { ^ . c last_proto }

@ http_client_last_pq * HttpClient c → b { ^ != . c last_pq 0 }

// Direct access to the cookie jar (seed a session cookie, inspect, …).
@ http_client_jar * HttpClient c → CookieJar { ^ . c jar }

// ── Origin pool ───────────────────────────────────────────────────────

@ __hc_origin_key s scheme s host i port → String {
    : String k ( string_from scheme )
    ( string_push_str k `://` )
    ( string_push_str k host )
    ( string_push_str k `:` )
    ( string_push_int k port )
    ^ k
}

// Find the pooled origin for `key`, or 0.
@ __hc_find_origin * HttpClient c s key → i {
    : i n ( vec_len [i] . c origins )
    : ~ i k 0
    : ~ i found 0
    ~ & == found 0 < k n {
        ?? ( vec_get [i] . c origins k ) {
            T p → {
                : *HcOrigin o # *HcOrigin p
                ? ( nurl_str_eq ( string_data . o key ) key ) { = found p } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ found
}

// Get or create the origin record for scheme://host:port (no connection
// opened yet).
@ __hc_origin * HttpClient c s scheme s host i port → *HcOrigin {
    : String key ( __hc_origin_key scheme host port )
    : i ex ( __hc_find_origin c ( string_data key ) )
    ? != ex 0 { ( string_free key ) ^ # *HcOrigin ex } {}
    : *HcOrigin o # *HcOrigin ( nurl_malloc Z HcOrigin )
    = . o key key
    = . o host ( string_from host )
    = . o port port
    = . o is_https ( nurl_str_eq scheme `https` )
    = . o proto 0
    = . o has_h2 0
    = . o has_h1 0
    = . o pq 0
    ( vec_push [i] . c origins # i o )
    ^ o
}

// Close whatever connection an origin holds (called on error / teardown).
@ __hc_origin_drop_conn * HcOrigin o → v {
    ? != . o has_h2 0 {
        ( h2_client_disconnect . o h2 )
        = . o has_h2 0
    } {}
    ? != . o has_h1 0 {
        ( hp_conn_close . o h1 )
        = . o has_h1 0
    } {}
    = . o proto 0
}

// ── Establishing a connection for an origin ───────────────────────────

// Ensure the origin has a usable connection, negotiating the protocol on
// first contact. Returns 0 on success, else an HttpClientErr-shaped code
// (mapped by __hc_conn_err). An https origin is dialled with ALPN
// "h2 http/1.1" and offered its cached TLS session; the negotiated ALPN
// decides h2 vs h1. Plaintext http is HTTP/1.1 only.
@ __hc_ensure_conn * HttpClient c * HcOrigin o → i {
    ? | != . o has_h2 0 != . o has_h1 0 { ^ 0 } {}
    ? != . o is_https 0 {
        : ( Vec u ) sess ( hp_session_lookup ( string_data . o host ) . o port )
        : !*TlsConn TlsErr tr ( tls_connect_full ( string_data . o host ) . o port ( string_data . o host ) `h2 http/1.1` sess . c verify )
        ( vec_free [u] sess )
        ?? tr {
            F e → { ^ ?? e { TlsBadCert → 3 TlsConnect → 1 _ → 3 } }
            T tc → {
                = . o pq ? ( tls_is_post_quantum tc ) 1 0
                : b is_h2 ( tls_alpn_is tc `h2` )
                ? is_h2 {
                    : TcpConn conn ( tcp_conn_from_tls tc )
                    : !H2Client H2ClientErr hr ( h2_client_attach conn )
                    ?? hr {
                        F _ → { ( tcp_close_conn conn ) ^ 6 }
                        T cl → {
                            = . o has_h2 1
                            = . o h2 cl
                            = . o proto 2
                            ^ 0
                        }
                    }
                } {
                    = . o h1 ( hp_conn_from_tls tc ( string_data . o host ) . o port )
                    ? > . c timeout_ms 0 { ( hp_conn_set_timeout . o h1 . c timeout_ms ) } {}
                    = . o has_h1 1
                    = . o proto 1
                    ^ 0
                }
            }
        }
    } {}
    // Plaintext HTTP/1.1.
    : !HttpConn i co ( hp_conn_open 0 ( string_data . o host ) . o port ( string_data . o host ) 0 )
    ?? co {
        F e → { ^ ? == e 1 1 6 }
        T conn → {
            = . o h1 conn
            ? > . c timeout_ms 0 { ( hp_conn_set_timeout . o h1 . c timeout_ms ) } {}
            = . o has_h1 1
            = . o proto 1
            ^ 0
        }
    }
}

@ __hc_conn_err i code → HttpClientErr {
    ? == code 1 { ^ # HttpClientErr HcConnect } {}
    ? == code 2 { ^ # HttpClientErr HcTimeout } {}
    ? == code 3 { ^ # HttpClientErr HcTls } {}
    ? == code 7 { ^ # HttpClientErr HcTooLarge } {}
    ^ # HttpClientErr HcOther
}

// ── Header assembly ───────────────────────────────────────────────────

// Build the request header blob for the h1 transport: the caller's
// headers, then a Cookie line (from the jar) and Accept-Encoding when
// decompression is on and the caller did not set them.
@ __hc_h1_headers * HttpClient c s host s path i is_https ( Vec Header ) user → String {
    : String blob ( string_new )
    : i n ( vec_len [Header] user )
    : *Header d ( vec_data [Header] user )
    : ~ i k 0
    ~ < k n {
        : Header h . d k
        ( string_push_str blob ( string_data . h name ) )
        ( string_push_str blob `: ` )
        ( string_push_str blob ( string_data . h value ) )
        ( string_push_str blob `\r\n` )
        = k + k 1
    }
    ? ! ( __hc_user_has user `cookie` ) {
        : String ck ( cookie_jar_header . c jar host path ? != is_https 0 T F ( now_seconds ) )
        ? > ( string_len ck ) 0 {
            ( string_push_str blob `Cookie: ` )
            ( string_push_str blob ( string_data ck ) )
            ( string_push_str blob `\r\n` )
        } {}
        ( string_free ck )
    } {}
    ? & != . c decompress 0 ! ( __hc_user_has user `accept-encoding` ) {
        ( string_push_str blob `Accept-Encoding: gzip, deflate\r\n` )
    } {}
    ^ blob
}

@ __hc_user_has ( Vec Header ) user s lname → b {
    : i n ( vec_len [Header] user )
    : *Header d ( vec_data [Header] user )
    : ~ i k 0
    : ~ b hit F
    ~ & ! hit < k n {
        : Header h . d k
        ? ( _hc_eq_ci ( string_data . h name ) lname ) { = hit T } {}
        = k + k 1
    }
    ^ hit
}

// ── One request over an origin (no redirects, no cookie storage) ──────
//
// Returns the unified HttpResponse or an HttpClientErr. `user` headers
// are BORROWED-consumed (freed here). `body` is BORROWED.
@ __hc_do * HttpClient c * HcOrigin o s method s path ( Vec Header ) user ( Vec u ) body → !HttpResponse HttpClientErr {
    : i ce ( __hc_ensure_conn c o )
    ? != ce 0 {
        ( __hc_free_headers user )
        ^ @ !HttpResponse HttpClientErr { F ( __hc_conn_err ce ) }
    } {}
    = . c last_proto . o proto
    = . c last_pq . o pq
    ? == . o proto 2 {
        ^ ( __hc_do_h2 c o method path user body )
    } {}
    ^ ( __hc_do_h1 c o method path user body )
}

@ __hc_free_headers ( Vec Header ) user → v {
    ( vec_free_with [Header] user \ Header h → v { ( header_free h ) } )
}

// HTTP/1.1 over the pooled keep-alive connection.
@ __hc_do_h1 * HttpClient c * HcOrigin o s method s path ( Vec Header ) user ( Vec u ) body → !HttpResponse HttpClientErr {
    : String blob ( __hc_h1_headers c ( string_data . o host ) path . o is_https user )
    ( __hc_free_headers user )
    // Detach the pooled conn; hp_stream_release re-pools it if reusable.
    : HttpConn conn . o h1
    = . o has_h1 0
    : *HttpStreamState st ( hp_stream_open_on conn method ( string_data . o host ) . o port . o is_https path ( vec_data [u] body ) ( vec_len [u] body ) ( string_data blob ) ( string_data . c ua ) )
    ( string_free blob )
    ? > . c body_max 0 { ( hp_stream_set_body_max st . c body_max ) } {}
    ~ == ( hp_stream_finished st ) 0 { ( hp_stream_pump st ) }
    : i ek ( hp_stream_err_kind st )
    ? != ek 0 {
        ( hp_stream_close st )
        = . o proto 0
        ^ @ !HttpResponse HttpClientErr { F ( __hc_stream_err ek ) }
    } {}
    : HttpResponse r ( __hc_response_from_stream c st )
    // Re-pool the connection when the response left it reusable.
    ?? ( hp_stream_release st ) {
        T back → { = . o h1 back = . o has_h1 1 }
        F _ → { = . o proto 0 }
    }
    ^ @ !HttpResponse HttpClientErr { T r }
}

@ __hc_stream_err i ek → HttpClientErr {
    ? == ek 1 { ^ # HttpClientErr HcConnect } {}
    ? == ek 2 { ^ # HttpClientErr HcTimeout } {}
    ? == ek 3 { ^ # HttpClientErr HcTls } {}
    ? == ek 7 { ^ # HttpClientErr HcTooLarge } {}
    ^ # HttpClientErr HcProtocol
}

// Assemble an HttpResponse (status, headers, body) from a finished h1
// stream, decoding the body if it is compressed and decompression is on.
@ __hc_response_from_stream * HttpClient c * HttpStreamState st → HttpResponse {
    : HttpResponse r ( response_new ( hp_stream_status st ) )
    : i hc ( hp_stream_header_count st )
    : ~ i k 0
    ~ < k hc {
        ( response_add_header r ( hp_stream_header_name st k ) ( hp_stream_header_value st k ) )
        = k + k 1
    }
    : ( Vec u ) raw ( hp_stream_body_take st )
    ( __hc_apply_body c r raw )
    ^ r
}

// ── HTTP/2 over the pooled multiplexed connection ─────────────────────
@ __hc_do_h2 * HttpClient c * HcOrigin o s method s path ( Vec Header ) user ( Vec u ) body → !HttpResponse HttpClientErr {
    // Pseudo-headers are added by h2_client_submit; we pass the regular
    // header list, adding Cookie / Accept-Encoding like the h1 path.
    : ( Vec Header ) hs ( vec_new [Header] )
    : i n ( vec_len [Header] user )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Header] user k ) { T h → ( vec_push [Header] hs h ) F _ → {} }
        = k + k 1
    }
    ( vec_free [Header] user )
    ? ! ( __hc_hlist_has hs `cookie` ) {
        : String ck ( cookie_jar_header . c jar ( string_data . o host ) path ? != . o is_https 0 T F ( now_seconds ) )
        ? > ( string_len ck ) 0 { ( vec_push [Header] hs ( header_new `cookie` ( string_data ck ) ) ) } {}
        ( string_free ck )
    } {}
    ? & != . c decompress 0 ! ( __hc_hlist_has hs `accept-encoding` ) {
        ( vec_push [Header] hs ( header_new `accept-encoding` `gzip, deflate` ) )
    } {}
    : ( Vec u ) bcopy ( vec_new [u] )
    ( bytes_extend_bytes bcopy body )
    : s scheme ? != . o is_https 0 `https` `http`
    : !i H2ClientErr sr ( h2_client_submit . o h2 method scheme ( string_data . o host ) path hs bcopy )
    ( __hc_free_headers hs )
    ?? sr {
        F _ → { ( __hc_origin_drop_conn o ) ^ @ !HttpResponse HttpClientErr { F # HttpClientErr HcProtocol } }
        T sid → {
            : !v H2ClientErr rr ( h2_client_run_until_complete . o h2 )
            ?? rr {
                F e → { ( __hc_origin_drop_conn o ) ^ @ !HttpResponse HttpClientErr { F ( __hc_h2_err e ) } }
                T _ → {
                    : !HttpResponse H2ClientErr tr ( h2_client_take_response . o h2 sid )
                    ?? tr {
                        F e → { ^ @ !HttpResponse HttpClientErr { F ( __hc_h2_err e ) } }
                        T resp → {
                            : HttpResponse dec ( __hc_decode_response c resp )
                            ^ @ !HttpResponse HttpClientErr { T dec }
                        }
                    }
                }
            }
        }
    }
}

@ __hc_h2_err H2ClientErr e → HttpClientErr {
    ^ ?? e {
        H2CConnect → # HttpClientErr HcConnect
        H2CTls → # HttpClientErr HcTls
        H2CAlpn → # HttpClientErr HcTls
        _ → # HttpClientErr HcProtocol
    }
}

@ __hc_hlist_has ( Vec Header ) hs s lname → b {
    : i n ( vec_len [Header] hs )
    : *Header d ( vec_data [Header] hs )
    : ~ i k 0
    : ~ b hit F
    ~ & ! hit < k n {
        : Header h . d k
        ? ( _hc_eq_ci ( string_data . h name ) lname ) { = hit T } {}
        = k + k 1
    }
    ^ hit
}

// Decompress an already-assembled HttpResponse's body in place (h2 path),
// returning a possibly-new HttpResponse.
@ __hc_decode_response * HttpClient c HttpResponse r → HttpResponse {
    ? == . c decompress 0 { ^ r } {}
    : String enc ( __hc_header_value . r headers `content-encoding` )
    : s ed ( string_data enc )
    ? | ( nurl_str_eq ed `gzip` ) ( nurl_str_eq ed `deflate` ) {
        : !( Vec u ) CompressErr dr ( gzip_decompress_max . r body ? > . c body_max 0 . c body_max 0 )
        ?? dr {
            T out → {
                ( vec_free [u] . r body )
                = . r body out
                ( __hc_strip_encoding r )
            }
            F _ → {}
        }
    } {}
    ( string_free enc )
    ^ r
}

// Decode a body Vec for the h1 path (response already built).
@ __hc_apply_body * HttpClient c HttpResponse r ( Vec u ) raw → v {
    ? == . c decompress 0 { ( response_set_body_bytes r raw ) ( vec_free [u] raw ) ^ v } {}
    : String enc ( __hc_header_value . r headers `content-encoding` )
    : s ed ( string_data enc )
    ? | ( nurl_str_eq ed `gzip` ) ( nurl_str_eq ed `deflate` ) {
        : !( Vec u ) CompressErr dr ( gzip_decompress_max raw ? > . c body_max 0 . c body_max 0 )
        ?? dr {
            T out → {
                ( response_set_body_bytes r out )
                ( vec_free [u] out )
                ( vec_free [u] raw )
                ( __hc_strip_encoding r )
                ( string_free enc )
                ^ v
            }
            F _ → {}
        }
    } {}
    ( string_free enc )
    ( response_set_body_bytes r raw )
    ( vec_free [u] raw )
}

// Drop the Content-Encoding header once we have decoded the body, so the
// caller does not double-decode.
@ __hc_strip_encoding HttpResponse r → v {
    : i n ( vec_len [Header] . r headers )
    : *Header d ( vec_data [Header] . r headers )
    : ~ i idx -1
    : ~ i k 0
    ~ & == idx -1 < k n {
        : Header h . d k
        ? ( _hc_eq_ci ( string_data . h name ) `content-encoding` ) { = idx k } {}
        = k + k 1
    }
    ? >= idx 0 {
        ?? ( vec_remove [Header] . r headers idx ) { T x → ( header_free x ) F _ → {} }
    } {}
}

@ __hc_header_value ( Vec Header ) hs s lname → String {
    : i n ( vec_len [Header] hs )
    : *Header d ( vec_data [Header] hs )
    : ~ i k 0
    ~ < k n {
        : Header h . d k
        ? ( _hc_eq_ci ( string_data . h name ) lname ) { ^ ( string_from ( string_data . h value ) ) } {}
        = k + k 1
    }
    ^ ( string_new )
}

// ── Cookie capture ────────────────────────────────────────────────────

// Store every Set-Cookie of a response into the jar.
@ __hc_capture_cookies * HttpClient c HttpResponse r s host s path → v {
    : i n ( vec_len [Header] . r headers )
    : *Header d ( vec_data [Header] . r headers )
    : ~ i k 0
    ~ < k n {
        : Header h . d k
        ? ( _hc_eq_ci ( string_data . h name ) `set-cookie` ) {
            : b _s ( cookie_jar_set . c jar ( string_data . h value ) host path ( now_seconds ) )
        } {}
        = k + k 1
    }
}

// ── The public request path (redirects + cookies) ─────────────────────

@ __hc_is_redirect i sc → b {
    ? | | == sc 301 == sc 302 == sc 303 { ^ T } {}
    ^ | == sc 307 == sc 308
}

// The one entry point: send `method` to `url` with `body` and the caller's
// `headers`, following redirects and carrying cookies. `headers` is
// consumed (freed); `body` is borrowed.
@ http_client_request * HttpClient c s method s url ( Vec Header ) headers ( Vec u ) body → !HttpResponse HttpClientErr {
    : ~ String cur_url ( string_from url )
    : ~ String cur_method ( string_from method )
    : ~ i redirects 0
    : ~ ( Vec Header ) hdrs headers
    : ~ i result_kind 0  // 0 pending, 1 ok, 2 err
    : ~ i err_code 0
    : ~ HttpResponse out ( response_new 0 )
    : ~ b looping T

    ~ looping {
        : ?Url maybe ( url_parse ( string_data cur_url ) )
        ?? maybe {
            F _ → {
                = result_kind 2
                = err_code 5
                = looping F
            }
            T u → {
                : s scheme ( string_data . u scheme )
                ? & == 0 ( nurl_str_eq scheme `http` ) == 0 ( nurl_str_eq scheme `https` ) {
                    ( url_free u )
                    = result_kind 2
                    = err_code 5
                    = looping F
                } {
                    : i port ( url_port_or_default u )
                    : String tgt ( url_request_target u )
                    : *HcOrigin o ( __hc_origin c scheme ( string_data . u host ) port )
                    // Copy the header list per attempt (each __hc_do consumes it).
                    : ( Vec Header ) attempt ( __hc_clone_headers hdrs )
                    : !HttpResponse HttpClientErr rr ( __hc_do c o ( string_data cur_method ) ( string_data tgt ) attempt body )
                    ?? rr {
                        F e → {
                            = result_kind 2
                            = err_code ( __hc_err_code e )
                            = looping F
                        }
                        T resp → {
                            ( __hc_capture_cookies c resp ( string_data . u host ) ( string_data tgt ) )
                            : i sc . resp status
                            : String loc ( __hc_header_value . resp headers `location` )
                            : b redir & & != . c follow 0 ( __hc_is_redirect sc ) > ( string_len loc ) 0
                            : b can < redirects . c max_redirects
                            ? & redir can {
                                : ?String nu ( _hp_resolve_redirect u ( string_data loc ) )
                                ?? nu {
                                    F _ → { ( http_response_free out ) = result_kind 1 = out resp = looping F }
                                    T nus → {
                                        ( http_response_free resp )
                                        ( string_free cur_url )
                                        = cur_url nus
                                        = redirects + redirects 1
                                        // 303, and 301/302 on a POST, become a bodyless GET.
                                        : b to_get | == sc 303 & | == sc 301 == sc 302 != 0 ( nurl_str_eq ( string_data cur_method ) `POST` )
                                        ? & to_get == 0 ( nurl_str_eq ( string_data cur_method ) `HEAD` ) {
                                            ( string_free cur_method )
                                            = cur_method ( string_from `GET` )
                                        } {}
                                    }
                                }
                            } {
                                ? & redir ! can {
                                    ( http_response_free resp )
                                    = result_kind 2
                                    = err_code 100  // too many redirects
                                } {
                                    ( http_response_free out )
                                    = result_kind 1
                                    = out resp
                                }
                                = looping F
                            }
                            ( string_free loc )
                        }
                    }
                    ( string_free tgt )
                    ( url_free u )
                }
            }
        }
    }
    ( __hc_free_headers hdrs )
    ( string_free cur_url )
    ( string_free cur_method )
    ? == result_kind 1 {
        ^ @ !HttpResponse HttpClientErr { T out }
    } {
        ( http_response_free out )
        ^ @ !HttpResponse HttpClientErr { F ? == err_code 100 # HttpClientErr HcTooManyRedirects ( __hc_conn_err err_code ) }
    }
}

@ __hc_err_code HttpClientErr e → i {
    ^ ?? e {
        HcConnect → 1
        HcTimeout → 2
        HcTls → 3
        HcDns → 4
        HcInvalidUrl → 5
        HcTooLarge → 7
        _ → 6
    }
}

@ __hc_clone_headers ( Vec Header ) hs → ( Vec Header ) {
    : ( Vec Header ) out ( vec_new [Header] )
    : i n ( vec_len [Header] hs )
    : *Header d ( vec_data [Header] hs )
    : ~ i k 0
    ~ < k n {
        : Header h . d k
        ( vec_push [Header] out ( header_new ( string_data . h name ) ( string_data . h value ) ) )
        = k + k 1
    }
    ^ out
}

// ── Convenience verbs ─────────────────────────────────────────────────

@ http_client_get * HttpClient c s url → !HttpResponse HttpClientErr {
    ^ ( __hc_bodyless c `GET` url )
}

@ http_client_head * HttpClient c s url → !HttpResponse HttpClientErr {
    ^ ( __hc_bodyless c `HEAD` url )
}

@ http_client_delete * HttpClient c s url → !HttpResponse HttpClientErr {
    ^ ( __hc_bodyless c `DELETE` url )
}

// A verb with no request body — the empty body Vec is ours, so free it
// once request has borrowed it.
@ __hc_bodyless * HttpClient c s method s url → !HttpResponse HttpClientErr {
    : ( Vec u ) empty ( vec_new [u] )
    : !HttpResponse HttpClientErr r ( http_client_request c method url ( vec_new [Header] ) empty )
    ( vec_free [u] empty )
    ^ r
}

// POST/PUT/PATCH with a body and a Content-Type. `body` is borrowed.
@ http_client_post * HttpClient c s url ( Vec u ) body s content_type → !HttpResponse HttpClientErr {
    ^ ( __hc_body_verb c `POST` url body content_type )
}

@ http_client_put * HttpClient c s url ( Vec u ) body s content_type → !HttpResponse HttpClientErr {
    ^ ( __hc_body_verb c `PUT` url body content_type )
}

@ http_client_patch * HttpClient c s url ( Vec u ) body s content_type → !HttpResponse HttpClientErr {
    ^ ( __hc_body_verb c `PATCH` url body content_type )
}

@ __hc_body_verb * HttpClient c s method s url ( Vec u ) body s content_type → !HttpResponse HttpClientErr {
    : ( Vec Header ) hs ( vec_new [Header] )
    ? > ( nurl_str_len content_type ) 0 { ( vec_push [Header] hs ( header_new `content-type` content_type ) ) } {}
    ^ ( http_client_request c method url hs body )
}

// Post a string body (text / JSON).
@ http_client_post_str * HttpClient c s url s body s content_type → !HttpResponse HttpClientErr {
    : ( Vec u ) b ( bytes_from_str body )
    : !HttpResponse HttpClientErr r ( http_client_post c url b content_type )
    ( vec_free [u] b )
    ^ r
}

// ── Response helpers (over the unified HttpResponse) ──────────────────

@ http_client_status HttpResponse r → i { ^ . r status }

// The response body as a borrowed String view (valid until free).
@ http_client_body_str HttpResponse r → String {
    ^ ( string_from_bytes ( vec_data [u] . r body ) ( vec_len [u] . r body ) )
}

@ http_client_header HttpResponse r s name → String {
    ^ ( __hc_header_value . r headers name )
}

// ── Teardown ──────────────────────────────────────────────────────────

@ http_client_free * HttpClient c → v {
    : i n ( vec_len [i] . c origins )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] . c origins k ) {
            T p → {
                : *HcOrigin o # *HcOrigin p
                ( __hc_origin_drop_conn o )
                ( string_free . o key )
                ( string_free . o host )
                ( nurl_free # s o )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [i] . c origins )
    ( cookie_jar_free . c jar )
    ( string_free . c ua )
    ( nurl_free # s c )
}
