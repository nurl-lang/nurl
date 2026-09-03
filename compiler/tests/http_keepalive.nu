// http_keepalive.nu — the pure HTTP/1.1 client's connection reuse,
// framing rules, deadlines and body cap (stdlib/ext/http_pure.nu).
//
// Until 2026-09-03 the client hardcoded `Connection: close`, ignored the
// timeouts it was handed, had no body cap, and read every body to EOF
// or Content-Length — a HEAD or 204 with a Content-Length would have
// hung on a keep-alive connection. This pins:
//   * hp_stream_open_on + hp_stream_release: three requests over ONE
//     accepted connection of the real HttpServer (one server_run_once);
//   * an interim 100 Continue is skipped, the final response is the one
//     reported, and the connection stays reusable;
//   * HEAD with Content-Length and 204 carry no body and keep the
//     connection; a body delimited by EOF, or `Connection: close`, does
//     not (release → none);
//   * the read deadline fires as error 2 (timeout), a Content-Length
//     body cut short by EOF as error 6, a body over the cap as error 7;
//   * redirect Location resolution (RFC 3986 §5.2) and the header-blob
//     probe that lets a caller take over Accept-Encoding / Connection.
//
// Servers on OS threads (tcp_accept blocks), client on the main thread.
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/url.nu`
$ `stdlib/ext/http_pure.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

: ~ i handled 0
: ~ i run_once_returns 0

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ yn b v → s { ^ ? v `T` `F` }

// ── canned server: one accepted connection per case ─────────────────

// Read until the request head is complete (or the peer goes away).
@ read_head TcpConn c → v {
    : ( Vec u ) acc ( vec_new [u] )
    : ~ b reading T
    ~ reading {
        ?? ( tcp_read_chunk c 4096 ) {
            T v → {
                ( bytes_extend_bytes acc v ) ( vec_free [u] v )
                : String s ( bytes_to_str acc )
                ? >= ( nurl_str_find ( string_data s ) `\r\n\r\n` ) 0 { = reading F } {}
                ( string_free s )
            }
            F _ → { = reading F }
        }
    }
    ( vec_free [u] acc )
}

@ send_text TcpConn c s text → v {
    : ( Vec u ) b ( bytes_from_str text )
    ?? ( tcp_write_all c b ) { T _ → {} F _ → {} }
    ( vec_free [u] b )
}

// One accepted connection: answer `first`; if `second` is non-empty read
// another request on the same connection and answer that too.
@ canned TcpListener l s first s second i delay_ms → v {
    ?? ( tcp_accept l ) {
        T c → {
            ( read_head c )
            ? > delay_ms 0 { ( sleep_ms delay_ms ) } {}
            ( send_text c first )
            ? > ( nurl_str_len second ) 0 {
                ( read_head c )
                ( send_text c second )
            } {}
            ( tcp_close_conn c )
        }
        F _ → {}
    }
}

@ big_body → String {
    : String r ( string_new )
    : ~ i k 0
    ~ < k 10000 { ( string_push_str r `x` ) = k + k 1 }
    ^ r
}

// ── client side ─────────────────────────────────────────────────────

// One exchange on `conn`; prints status/body/err, returns the released
// transport (none when the response made it single-use).
@ exchange s name HttpConn conn s method s target i body_max → ?HttpConn {
    : *HttpStreamState st ( hp_stream_open_on conn method `127.0.0.1` 18951 0 target # *u 0 0 `` `nurl-test` )
    ( hp_stream_set_body_max st body_max )
    ~ == . st finished 0 { ( hp_stream_pump st ) }
    : String v ( string_new )
    ? != . st err_kind 0 {
        ( string_push_str v `err=` )
        ( string_push_int v . st err_kind )
    } {
        ( string_push_int v . st status )
        ( string_push_str v ` body=[` )
        : i bl ( vec_len [u] . st body )
        ? > bl 20 {
            ( string_push_int v bl )
            ( string_push_str v ` bytes` )
        } {
            : String b ( string_from_bytes ( vec_data [u] . st body ) bl )
            ( string_push_str v ( string_data b ) )
            ( string_free b )
        }
        ( string_push_str v `]` )
    }
    : ?HttpConn back ( hp_stream_release st )
    ( string_push_str v ` reusable=` )
    ?? back { T _ → { ( string_push_str v `T` ) } F _ → { ( string_push_str v `F` ) } }
    ( label name ( string_data v ) )
    ( string_free v )
    ^ back
}

@ open_conn i timeout_ms → ?HttpConn {
    ?? ( hp_conn_open 0 `127.0.0.1` 18951 `127.0.0.1` 0 ) {
        T c → {
            ? > timeout_ms 0 { ( hp_conn_set_timeout c timeout_ms ) } {}
            ^ @ ?HttpConn { T c }
        }
        F e → { ( label `connect` `FAIL` ) ^ @ ?HttpConn { F # HttpConn 0 } }
    }
}

@ drop_conn ? HttpConn c → v {
    ?? c { T x → ( hp_conn_close x ) F _ → {} }
}

@ canned_cases TcpListener l → v {
    : s h100 `HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok`
    : s h_head `HTTP/1.1 200 OK\r\nContent-Length: 1000\r\nETag: "x"\r\n\r\n`
    : s h204 `HTTP/1.1 204 No Content\r\n\r\n`
    : s h_eof `HTTP/1.1 200 OK\r\n\r\nhello`
    : s h_close `HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nbye`
    : s h_short `HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc`
    : s h10 `HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok`
    : s h_10 `HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok`
    : s h_10ka `HTTP/1.0 200 OK\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nok`
    : String big ( big_body )
    : String h_big ( string_from `HTTP/1.1 200 OK\r\nContent-Length: 10000\r\n\r\n` )
    ( string_push_str h_big ( string_data big ) )
    : s chunked `HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n`

    ( canned l h100 h10 0 )  // 1: interim skipped, then reused
    ( canned l h_head h204 0 )  // 2: HEAD + 204 on one connection
    ( canned l h_eof `` 0 )  // 3: EOF-delimited
    ( canned l h_close `` 0 )  // 4: Connection: close
    ( canned l h10 `` 900 )  // 5: deadline
    ( canned l h_short `` 0 )  // 6: truncated
    ( canned l ( string_data h_big ) `` 0 )  // 7: over the cap
    ( canned l chunked h10 0 )  // 8: chunked then reused
    ( canned l h_10 `` 0 )  // 9: HTTP/1.0 → single use
    ( canned l h_10ka `` 0 )  // 10: HTTP/1.0 + keep-alive → reusable
    ( string_free big )
    ( string_free h_big )
}

// ── the real HttpServer: three requests, one connection ─────────────

@ count_handler HttpRequest req → HttpResponse {
    = handled + handled 1
    : String body ( string_from `req ` )
    ( string_push_int body handled )
    ( string_push_str body ` ` )
    ( string_push_str body ( string_data . req path ) )
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( string_free body )
    ^ r
}

@ real_server_case → v {
    ?? ( hp_conn_open 0 `127.0.0.1` 18952 `127.0.0.1` 0 ) {
        T c0 → {
            : ~ ? HttpConn cur @ ?HttpConn { T c0 }
            : ~ i k 1
            ~ <= k 3 {
                ?? cur {
                    T c → {
                        : String tg ( string_from `/n` )
                        ( string_push_int tg k )
                        : *HttpStreamState st ( hp_stream_open_on c `GET` `127.0.0.1` 18952 0 ( string_data tg ) # *u 0 0 `` `nurl-test` )
                        ~ == . st finished 0 { ( hp_stream_pump st ) }
                        : String v ( string_new )
                        ( string_push_int v . st status )
                        ( string_push_str v ` ` )
                        : String b ( string_from_bytes ( vec_data [u] . st body ) ( vec_len [u] . st body ) )
                        ( string_push_str v ( string_data b ) )
                        : String nm ( string_from `server_req` )
                        ( string_push_int nm k )
                        ( label ( string_data nm ) ( string_data v ) )
                        ( string_free nm ) ( string_free b ) ( string_free v ) ( string_free tg )
                        = cur ( hp_stream_release st )
                    }
                    F _ → { ( label `server_conn_lost` `T` ) = k 99 }
                }
                = k + k 1
            }
            ( drop_conn cur )
        }
        F _ → { ( label `server_connect` `FAIL` ) }
    }
}

// ── offline: Location resolution and the header-blob probe ──────────

@ resolve s base s loc → s {
    ?? ( url_parse base ) {
        T u → {
            : ?String r ( _hp_resolve_redirect u loc )
            ( url_free u )
            ?? r { T s → ^ ( string_data s ) F _ → ^ `(none)` }
        }
        F _ → ^ `(bad base)`
    }
}

@ offline → v {
    ( label `abs` ( resolve `http://a/b/c/d;p?q` `https://x.example/y#frag` ) )
    ( label `scheme_rel` ( resolve `https://a:8443/b/c` `//other/p` ) )
    ( label `root_rel` ( resolve `https://a:8443/b/c?q` `/g?x=1` ) )
    ( label `path_rel` ( resolve `http://a/b/c/d;p?q` `g` ) )
    ( label `dotdot` ( resolve `http://a/b/c/d;p?q` `../g` ) )
    ( label `dotdot2` ( resolve `http://a/b/c/d;p?q` `../../g` ) )
    ( label `dotdot_over` ( resolve `http://a/b/c/d;p?q` `../../../g` ) )
    ( label `dot` ( resolve `http://a/b/c/d;p?q` `./g/.` ) )
    ( label `query_only` ( resolve `http://a/b/c/d;p?q` `?y` ) )
    ( label `empty_path_base` ( resolve `http://a` `g` ) )
    ( label `blob_has_ae` ( yn ( _hp_blob_has `Accept-Encoding: gzip\r\n` `accept-encoding` ) ) )
    ( label `blob_has_ae_second` ( yn ( _hp_blob_has `X: 1\r\naccept-encoding: br\r\n` `accept-encoding` ) ) )
    ( label `blob_has_ae_not_value` ( yn ( _hp_blob_has `X: accept-encoding: gzip\r\n` `accept-encoding` ) ) )
    ( label `blob_has_ae_prefix` ( yn ( _hp_blob_has `Accept-Encodings: gzip\r\n` `accept-encoding` ) ) )
    ( label `blob_has_empty` ( yn ( _hp_blob_has `` `connection` ) ) )
}

@ run → v {
    ( offline )
    : !TcpListener NetErr lr1 ( tcp_listen `127.0.0.1` 18951 )
    : !TcpListener NetErr lr2 ( tcp_listen `127.0.0.1` 18952 )
    ?? lr1 {
        T l1 → {
            ?? lr2 {
                T l2 → {
                    : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse { ^ ( count_handler req ) }
                    : HttpServer srv ( server_new_with_timeout l2 handler 5000 )
                    : ( @ v ) server \ → v {
                        ( canned_cases l1 )
                        : !v NetErr r1 ( server_run_once srv )
                        = run_once_returns + run_once_returns 1
                    }
                    ?? ( thread_spawn server ) {
                        T t → {
                            ( sleep_ms 150 )
                            // 1. 100 Continue skipped; reuse for a second request
                            : ?HttpConn c1 ( open_conn 0 )
                            ?? c1 {
                                T c → {
                                    : ?HttpConn c1b ( exchange `interim_100` c `GET` `/a` 0 )
                                    ?? c1b {
                                        T cc → { ( drop_conn ( exchange `interim_100_reuse` cc `GET` `/b` 0 ) ) }
                                        F _ → { ( label `interim_100_reuse` `no conn` ) }
                                    }
                                }
                                F _ → {}
                            }
                            // 2. HEAD with Content-Length, then 204, one connection
                            : ?HttpConn c2 ( open_conn 0 )
                            ?? c2 {
                                T c → {
                                    : ?HttpConn c2b ( exchange `head_clen` c `HEAD` `/h` 0 )
                                    ?? c2b {
                                        T cc → { ( drop_conn ( exchange `no_content_204` cc `GET` `/n` 0 ) ) }
                                        F _ → { ( label `no_content_204` `no conn` ) }
                                    }
                                }
                                F _ → {}
                            }
                            // 3. body to EOF
                            : ?HttpConn c3 ( open_conn 0 )
                            ?? c3 { T c → { ( drop_conn ( exchange `eof_body` c `GET` `/e` 0 ) ) } F _ → {} }
                            // 4. Connection: close
                            : ?HttpConn c4 ( open_conn 0 )
                            ?? c4 { T c → { ( drop_conn ( exchange `conn_close` c `GET` `/c` 0 ) ) } F _ → {} }
                            // 5. deadline 250 ms, server answers after 900 ms
                            : ?HttpConn c5 ( open_conn 250 )
                            ?? c5 { T c → { ( drop_conn ( exchange `deadline` c `GET` `/t` 0 ) ) } F _ → {} }
                            // 6. Content-Length 10, 3 bytes then EOF
                            : ?HttpConn c6 ( open_conn 0 )
                            ?? c6 { T c → { ( drop_conn ( exchange `truncated` c `GET` `/s` 0 ) ) } F _ → {} }
                            // 7. 10000-byte body against a 100-byte cap
                            : ?HttpConn c7 ( open_conn 0 )
                            ?? c7 { T c → { ( drop_conn ( exchange `over_cap` c `GET` `/big` 100 ) ) } F _ → {} }
                            // 8. chunked, then reuse
                            : ?HttpConn c8 ( open_conn 0 )
                            ?? c8 {
                                T c → {
                                    : ?HttpConn c8b ( exchange `chunked` c `GET` `/ch` 0 )
                                    ?? c8b {
                                        T cc → { ( drop_conn ( exchange `chunked_reuse` cc `GET` `/b` 0 ) ) }
                                        F _ → { ( label `chunked_reuse` `no conn` ) }
                                    }
                                }
                                F _ → {}
                            }
                            // 9. HTTP/1.0 response → single use
                            : ?HttpConn c9 ( open_conn 0 )
                            ?? c9 { T c → { ( drop_conn ( exchange `http10` c `GET` `/o` 0 ) ) } F _ → {} }
                            // 10. HTTP/1.0 + Connection: keep-alive → reusable
                            : ?HttpConn c10 ( open_conn 0 )
                            ?? c10 { T c → { ( drop_conn ( exchange `http10_keepalive` c `GET` `/o` 0 ) ) } F _ → {} }

                            ( real_server_case )
                            ( thread_join t )
                            : *u env # *u server 1
                            ( nurl_free # s env )
                            ( label `server_handled` ( nurl_str_int handled ) )
                            ( label `server_run_once_returns` ( nurl_str_int run_once_returns ) )
                        }
                        F _ → { ( label `thread` `FAIL` ) }
                    }
                    ( server_stop srv )
                }
                F e → { ( label `listen2` ( net_err_name e ) ) }
            }
            ( tcp_close_listener l1 )
        }
        F e → { ( label `listen1` ( net_err_name e ) ) }
    }
}

@ main → i {
    ( run )
    ^ 0
}
