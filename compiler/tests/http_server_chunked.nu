// http_server_chunked.nu — live regression for chunked request bodies on
// a keep-alive connection (stdlib/ext/http_server.nu). Gated behind
// NURL_NET_TESTS=1 (opens a loopback socket + spawns a server thread).
//
// Before the fix, _finish_body only handled Content-Length: a
// Transfer-Encoding: chunked body was left undrained in the connection
// carry buffer — the handler saw an EMPTY body, and the leftover bytes
// were mis-parsed as the next request (a desync / smuggling vector).
//
// This drives ONE keep-alive connection with two pipelined-style
// requests: a chunked POST (body "hello world", 11 bytes) followed by a
// plain GET. The handler echoes `len=<bodylen> path=<path>`. We assert:
//   * the POST handler saw 11 body bytes (chunked decoded, not dropped);
//   * the GET response is present and correct (no keep-alive desync).
//
// main returns the failure count.

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

// Raw client connect (no high-level tcp_connect exists; mirror the
// http2_client / websocket client shape).
& `libc` @ nurl_tcp_connect s host i port → i

@ echo_handler HttpRequest req → HttpResponse {
    : String b ( string_from `len=` )
    ( string_push_str b ( nurl_str_int ( vec_len [u] . req body ) ) )
    ( string_push_str b ` path=` )
    ( string_push_str b ( string_data . req path ) )
    : HttpResponse r ( response_text 200 ( string_data b ) )
    ( string_free b )
    ^ r
}

// Read from the client socket until `buf` contains `needle` or we hit a
// few empty/again reads. Best-effort — enough to collect two small
// pipelined responses on loopback.
@ drain_until TcpConn conn String buf s needle → v {
    ( tcp_set_timeout conn 2000 )
    : ~ i tries 0
    : ~ b done F
    ~ & ! done < tries 40 {
        ? ( __buf_has buf needle ) { = done T } {
            : !( Vec u ) NetErr r ( tcp_read_chunk conn 4096 )
            ?? r {
                T chunk → {
                    : i got ( vec_len [u] chunk )
                    ? > got 0 { ( bytes_extend_str_from buf chunk ) } { = tries + tries 1 }
                    ( vec_free [u] chunk )
                }
                F _ → { = tries + tries 1 }
            }
        }
    }
}

@ __buf_has String buf s needle → b {
    ^ ( string_contains buf needle )
}

@ bytes_extend_str_from String buf ( Vec u ) chunk → v {
    : i n ( vec_len [u] chunk )
    : *u p ( vec_data [u] chunk )
    : ~ i k 0
    ~ < k n {
        ( string_push_char buf & 255 # i . p k )
        = k + k 1
    }
}

@ run_live → i {
    : ~ i fails 0
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18823 )
    ?? lr {
        T listener → {
            : HttpServer srv ( server_new listener \ HttpRequest req → HttpResponse { ^ ( echo_handler req ) } )
            : ( @ v ) server_fn \ → v {
                : !v NetErr r ( server_run_once srv )
                ?? r { T _ → {} F _ → {} }
            }
            : !Thread ThreadErr st ( thread_spawn server_fn )
            ( sleep_ms 100 )

            : i craw ( nurl_tcp_connect `127.0.0.1` 18823 )
            : i cek ( nurl_tcp_err_kind craw )
            ? != cek 0 {
                ( nurl_print `  FAIL connect\n` ) = fails + fails 1
            } {
                : TcpConn conn @ TcpConn { # s craw }
                {
                    // Chunked POST: "hello" + " world" = 11 bytes, then a GET.
                    : ( Vec u ) wbuf ( vec_new [u] )
                    ( bytes_extend_str wbuf `POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n` )
                    ( bytes_extend_str wbuf `GET /ping HTTP/1.1\r\nHost: x\r\n\r\n` )
                    : !v NetErr ww ( tcp_write_all conn wbuf )
                    ( vec_free [u] wbuf )
                    ?? ww { T _ → {} F _ → { = fails + fails 1 } }

                    : String resp ( string_new )
                    ( drain_until conn resp `path=/ping` )

                    // POST body must have decoded to 11 bytes (not dropped).
                    ? ( __buf_has resp `len=11 path=/echo` ) {} {
                        ( nurl_print `  FAIL chunked body not decoded\n` ) = fails + fails 1
                    }
                    // GET after the chunked POST must parse cleanly (no desync).
                    ? ( __buf_has resp `len=0 path=/ping` ) {} {
                        ( nurl_print `  FAIL keep-alive desync after chunked\n` ) = fails + fails 1
                    }
                    ( string_free resp )
                    ( tcp_close_conn conn )
                }
            }
            : i _sj ?? st { T th → ( thread_join th ) F _ → 0 }
            ( tcp_close_listener listener )
        }
        F _ → { ( nurl_print `  FAIL listen\n` ) = fails + fails 1 }
    }
    ^ fails
}

@ main → i {
    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → {
            ( string_free s )
            : i f ( run_live )
            ? == f 0 { ( nurl_print `chunked keep-alive ok\n` ) } {}
            ^ f
        }
        F → { ( nurl_print `http_server_chunked skipped (NURL_NET_TESTS != 1)\n` ) ^ 0 }
    }
}
