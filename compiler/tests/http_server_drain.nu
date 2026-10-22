// http_server_drain.nu — server_drain, the graceful stop (agora #54),
// on the thread pool (server_run_pool) and on fibers (server_run_async).
//
// Per mode, one server and a controlling thread:
//   * a keep-alive connection that has been answered once and sits idle
//     is closed as soon as the drain begins (EOF well inside a second,
//     against a 20 s idle timeout);
//   * a request in flight when the drain begins (its handler sleeps
//     400 ms) is answered — 200, with `Connection: close` — and then the
//     connection closes;
//   * an HTTP/2 connection (prior knowledge, idle) is sent GOAWAY
//     (NO_ERROR) and closed;
//   * server_drain returns T (everything finished before the deadline),
//     the run call returns, and a new connection is refused.
// Then the deadline: a handler that sleeps 2.5 s outlives a 200 ms drain;
// server_drain returns F well before the handler would have finished, and
// that client sees the connection close with no response.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`

@ handler HttpRequest req → HttpResponse {
    : s path ( string_data . req path )
    ? != 0 ( nurl_str_eq path `/slow` ) { ( sleep_ms 400 ) } {}
    ? != 0 ( nurl_str_eq path `/stuck` ) { ( sleep_ms 2500 ) } {}
    ^ ( response_text 200 `done\n` )
}

// Everything the peer sends until it closes (or `limit` bytes / an error).
@ read_to_eof TcpConn c → String {
    : ( Vec u ) acc ( vec_new [u] )
    : ~ b reading T
    ~ reading {
        ?? ( tcp_read_chunk c 4096 ) {
            T v → {
                ? == ( vec_len [u] v ) 0 { = reading F } { ( bytes_extend_bytes acc v ) }
            }
            F _ → { = reading F }
        }
    }
    ^ ( bytes_to_str acc )
}

// One request, its whole response read (it ends in `done\n`).
@ request_once TcpConn c s path → b {
    : String req ( string_from `GET ` )
    ( string_push_str req path )
    ( string_push_str req ` HTTP/1.1\r\nHost: x\r\n\r\n` )
    ?? ( tcp_write_all c ( bytes_from_str ( string_data req ) ) ) { T _ → {} F _ → { ^ F } }
    : ( Vec u ) acc ( vec_new [u] )
    ~ T {
        ?? ( tcp_read_chunk c 4096 ) {
            T v → {
                ? == ( vec_len [u] v ) 0 { ^ F } {}
                ( bytes_extend_bytes acc v )
                : String s ( bytes_to_str acc )
                ? >= ( nurl_str_find ( string_data s ) `done\n` ) 0 { ^ T } {}
            }
            F _ → { ^ F }
        }
    }
    ^ F
}

// The frame types in an HTTP/2 byte stream, as "4,4,7," …
@ h2_frame_types String s → String {
    : ( Slice u ) b ( string_bytes s )
    : i n ( slice_len [u] b )
    : String out ( string_new )
    : ~ i at 0
    ~ <= + at 9 n {
        : i len + + * 65536 ( slice_byte b at ) * 256 ( slice_byte b + at 1 ) ( slice_byte b + at 2 )
        ( string_push_int out ( slice_byte b + at 3 ) )
        ( string_push_str out `,` )
        = at + + at 9 len
    }
    ^ out
}

: ~ b slow_ok F
: ~ b slow_close F
: ~ i idle_eof_ms -1
: ~ b goaway F
: ~ b drained F
: ~ i drain_ms -1
: ~ b refused F
: ~ b stuck_no_response F

@ check_drain HttpServer srv i port → v {
    ( sleep_ms 200 )
    // An idle keep-alive connection: answered once, then left open.
    ?? ( tcp_connect `127.0.0.1` port ) {
        T idle → {
            : b _first ( request_once idle `/fast` )
            // An idle HTTP/2 connection, by prior knowledge.
            ?? ( tcp_connect `127.0.0.1` port ) {
                T h2 → {
                    : ( Vec u ) pre ( bytes_from_str `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n` )
                    ( vec_push [u] pre # u 0 ) ( vec_push [u] pre # u 0 ) ( vec_push [u] pre # u 0 )
                    ( vec_push [u] pre # u 4 ) ( vec_push [u] pre # u 0 )
                    ( vec_push [u] pre # u 0 ) ( vec_push [u] pre # u 0 ) ( vec_push [u] pre # u 0 ) ( vec_push [u] pre # u 0 )
                    ?? ( tcp_write_all h2 pre ) { T _ → {} F _ → {} }
                    // A request in flight: its own connection, its own thread.
                    : ( @ v ) slow \ → v {
                        ?? ( tcp_connect `127.0.0.1` port ) {
                            T c → {
                                ?? ( tcp_write_all c ( bytes_from_str `GET /slow HTTP/1.1\r\nHost: x\r\n\r\n` ) ) { T _ → {} F _ → {} }
                                : String r ( read_to_eof c )
                                = slow_ok >= ( nurl_str_find ( string_data r ) `200 OK` ) 0
                                = slow_close >= ( nurl_str_find ( string_data r ) `Connection: close` ) 0
                            }
                            F _ → {}
                        }
                    }
                    : !Thread ThreadErr st ( thread_spawn slow )
                    ( sleep_ms 150 )
                    : i t0 ( now_ms )
                    // The idle connections' EOFs, timed on threads of their own.
                    : ( @ v ) idle_watch \ → v {
                        : String _r ( read_to_eof idle )
                        = idle_eof_ms - ( now_ms ) t0
                    }
                    : ( @ v ) h2_watch \ → v {
                        : String r ( read_to_eof h2 )
                        : String types ( h2_frame_types r )
                        = goaway >= ( nurl_str_find ( string_data types ) `7,` ) 0
                    }
                    : !Thread ThreadErr it ( thread_spawn idle_watch )
                    : !Thread ThreadErr ht ( thread_spawn h2_watch )
                    = drained ( server_drain srv 5000 )
                    = drain_ms - ( now_ms ) t0
                    ?? st { T t → { ( thread_join t ) } F _ → {} }
                    ?? it { T t → { ( thread_join t ) } F _ → {} }
                    ?? ht { T t → { ( thread_join t ) } F _ → {} }
                    ?? ( tcp_connect `127.0.0.1` port ) { T c → { ( tcp_close_conn c ) } F _ → { = refused T } }
                }
                F _ → { ( nurl_println `h2 connect FAIL` ) }
            }
        }
        F _ → { ( nurl_println `connect FAIL` ) }
    }
}

@ check_deadline HttpServer srv i port → v {
    ( sleep_ms 200 )
    : ( @ v ) stuck \ → v {
        ?? ( tcp_connect `127.0.0.1` port ) {
            T c → {
                ?? ( tcp_write_all c ( bytes_from_str `GET /stuck HTTP/1.1\r\nHost: x\r\n\r\n` ) ) { T _ → {} F _ → {} }
                : String r ( read_to_eof c )
                = stuck_no_response == 0 ( string_len r )
            }
            F _ → {}
        }
    }
    : !Thread ThreadErr st ( thread_spawn stuck )
    ( sleep_ms 150 )
    : i t0 ( now_ms )
    = drained ( server_drain srv 200 )
    = drain_ms - ( now_ms ) t0
    ?? st { T t → { ( thread_join t ) } F _ → {} }
}

@ yn b x → s { ^ ? x `T` `F` }

@ run s name i port b fiber b deadline → v {
    ?? ( tcp_listen `127.0.0.1` port ) {
        T l → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse { ^ ( handler req ) }
            : HttpServer srv ( server_new_with_timeout l h 20000 )
            : ( @ v ) ctl \ → v { ? deadline { ( check_deadline srv port ) } { ( check_drain srv port ) } }
            : !Thread ThreadErr ct ( thread_spawn ctl )
            ? fiber {
                ?? ( server_run_async srv ) { T _ → {} F _ → {} }
            } {
                ?? ( server_run_pool srv 4 ) { T _ → {} F _ → {} }
            }
            ?? ct { T t → { ( thread_join t ) } F _ → {} }
            ( nurl_print name )
            ? deadline {
                ( nurl_print ` drained-in-time=` ) ( nurl_print ( yn drained ) )
                ( nurl_print ` returned-before-handler=` ) ( nurl_print ( yn < drain_ms 2000 ) )
                ( nurl_print ` stuck-client-no-response=` ) ( nurl_println ( yn stuck_no_response ) )
            } {
                ( nurl_print ` drained-in-time=` ) ( nurl_print ( yn drained ) )
                ( nurl_print ` in-flight-200=` ) ( nurl_print ( yn slow_ok ) )
                ( nurl_print ` with-close=` ) ( nurl_print ( yn slow_close ) )
                ( nurl_print ` idle-closed-promptly=` ) ( nurl_print ( yn & >= idle_eof_ms 0 < idle_eof_ms 1000 ) )
                ( nurl_print ` h2-goaway=` ) ( nurl_print ( yn goaway ) )
                ( nurl_print ` new-conn-refused=` ) ( nurl_println ( yn refused ) )
            }
            = slow_ok F = slow_close F = idle_eof_ms -1 = goaway F = drained F = refused F = stuck_no_response F
        }
        F _ → { ( nurl_println `listen FAIL` ) }
    }
}

@ main → i {
    ( run `pool` 18991 F F )
    ( run `pool-deadline` 18992 F T )
    ( runtime_init 2 )
    ( run `fiber` 18993 T F )
    ( run `fiber-deadline` 18994 T T )
    ( runtime_shutdown )
    ^ 0
}
