// http_keepalive_cap_modes.nu — the per-mode keep-alive request cap.
//
// A connection served on a worker THREAD (server_run, server_run_pool)
// holds that thread, so the default cap (server_default_max_keepalive_
// requests, 1000) closes it after its 1000th request. A connection
// served on a FIBER (server_run_async) holds only the fiber: the default
// there is no cap, and the idle timeout is what bounds it — a cap would
// only make the client reconnect, and the server re-accept and re-spawn
// a fiber, every 1000 requests. Pins:
//   * thread, default:      1000 answered, the 1000th says close;
//   * fiber, default:       all 1005 answered, none says close;
//   * fiber, explicit cap 3: 3 answered, the 3rd says close (an explicit
//     cap is honoured on a fiber too);
//   * fiber, explicit server_keepalive_unlimited: all answered.
//
// The client is a blocking pthread sending one request at a time on one
// connection; the server runs on the main thread.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`

: ~ i answered 0
: ~ i close_at 0

@ ok_handler HttpRequest r → HttpResponse {
    ^ ( response_text 200 `ok\n` )
}

// Read one whole response (it ends with the `ok\n` body). F when the
// server closed the connection first. Records the request number whose
// response carries `Connection: close`.
@ read_response TcpConn c i n → b {
    : ( Vec u ) acc ( vec_new [u] )
    : ~ b got F
    : ~ b reading T
    ~ reading {
        ?? ( tcp_read_chunk c 4096 ) {
            T v → {
                ( bytes_extend_bytes acc v )
                : String s ( bytes_to_str acc )
                ? >= ( nurl_str_find ( string_data s ) `\r\n\r\nok\n` ) 0 {
                    = got T
                    = reading F
                    ? >= ( nurl_str_find ( string_data s ) `onnection: close` ) 0 {
                        ? == close_at 0 { = close_at n } {}
                    } {}
                } {}
                ? == ( vec_len [u] v ) 0 { = reading F } {}
            }
            F _ → { = reading F }
        }
    }
    ^ got
}

// Send up to `total` requests on one connection, counting the answers.
@ client_run i port i total → v {
    ( sleep_ms 150 )
    ?? ( tcp_connect `127.0.0.1` port ) {
        T c → {
            : ~ i k 1
            ~ <= k total {
                : ( Vec u ) req ( bytes_from_str `GET / HTTP/1.1\r\nHost: localhost\r\n\r\n` )
                : ~ b sent F
                ?? ( tcp_write_all c req ) { T _ → { = sent T } F _ → {} }
                ? & sent ( read_response c k ) {
                    = answered + answered 1
                    = k + k 1
                } {
                    = k + total 1
                }
            }
            ( tcp_close_conn c )
        }
        F _ → { ( nurl_print `connect FAIL\n` ) }
    }
}

@ report s name → v {
    ( nurl_print name )
    ( nurl_print ` answered=` )
    ( nurl_print ( nurl_str_int answered ) )
    ( nurl_print ` close_at=` )
    ( nurl_print ( nurl_str_int close_at ) )
    ( nurl_print `\n` )
    = answered 0
    = close_at 0
}

// One case: a server with `cap` (server_keepalive_auto = the default),
// on a thread (`fiber` F, server_run) or on fibers (server_run_async;
// the runtime is initialised once, by main, around every fiber case).
@ run_case s name i port i cap b fiber i total → v {
    ?? ( tcp_listen `127.0.0.1` port ) {
        T l → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse { ^ ( ok_handler req ) }
            : HttpServer srv ( server_new_full l h 5000 cap )
            : ( @ v ) client \ → v {
                ( client_run port total )
                ( server_stop srv )
            }
            : !Thread ThreadErr ct ( thread_spawn client )
            ? fiber {
                ?? ( server_run_async srv ) { T _ → {} F _ → {} }
            } {
                ?? ( server_run srv ) { T _ → {} F _ → {} }
            }
            ?? ct { T t → { ( thread_join t ) } F _ → {} }
            ( report name )
        }
        F _ → { ( nurl_print `listen FAIL\n` ) }
    }
}

@ main → i {
    ( run_case `thread_default` 18971 ( server_keepalive_auto ) F 1005 )
    ( runtime_init 2 )
    ( run_case `fiber_default` 18972 ( server_keepalive_auto ) T 1005 )
    ( run_case `fiber_cap3` 18973 3 T 10 )
    ( run_case `fiber_unlimited` 18974 ( server_keepalive_unlimited ) T 1005 )
    ( runtime_shutdown )
    ^ 0
}
