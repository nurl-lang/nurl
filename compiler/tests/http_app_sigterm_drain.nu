// http_app_sigterm_drain.nu — the packages/http facade drains on SIGTERM
// (agora #54): the signal closes the listener, an idle keep-alive
// connection is closed at once (not after its 20 s idle timeout), a
// request in flight is answered with `Connection: close`, and
// http_app_listen returns 0.
//
// Ordered by events, not sleeps: SIGTERM is raised once the /slow handler
// is running, and the handler answers once the idle connection has been
// closed — the drain has begun, so the response is composed while the
// server drains. A fixed 400 ms handler lost that race on a loaded runner
// (`with-close=F`, agora #539).
// requires: live

$ `stdlib/core/string.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `packages/http/src/http.nu`

: ~ b slow_ok F
: ~ b slow_close F
: ~ i idle_eof_ms -1
: ~ b slow_started F
: ~ b idle_gone F

// Wait (10 ms steps, 5 s at most) until `flag` reads true.
@ wait_for ( @ b ) flag → v {
    : ~ i waited 0
    ~ & ! ( flag ) < waited 5000 {
        ( sleep_ms 10 )
        = waited + waited 10
    }
}

@ read_to_eof TcpConn c → String {
    : ( Vec u ) acc ( vec_new [u] )
    : ~ b reading T
    ~ reading {
        ?? ( tcp_read_chunk c 4096 ) {
            T v → { ? == ( vec_len [u] v ) 0 { = reading F } { ( bytes_extend_bytes acc v ) } }
            F _ → { = reading F }
        }
    }
    ^ ( bytes_to_str acc )
}

@ ctl i port → v {
    ( sleep_ms 300 )
    ?? ( tcp_connect `127.0.0.1` port ) {
        T idle → {
            ?? ( tcp_write_all idle ( bytes_from_str `GET /fast HTTP/1.1\r\nHost: x\r\n\r\n` ) ) { T _ → {} F _ → {} }
            ?? ( tcp_read_chunk idle 4096 ) { T _ → {} F _ → {} }
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
            ( wait_for \ → b { ^ slow_started } )
            : i t0 ( now_ms )
            : i _r ( signal_raise ( signal_constant `SIGTERM` ) )
            : String _e ( read_to_eof idle )
            = idle_eof_ms - ( now_ms ) t0
            = idle_gone T
            ?? st { T t → { ( thread_join t ) } F _ → {} }
        }
        F _ → { ( nurl_println `connect FAIL` ) }
    }
}

@ main → i {
    : HttpApp a ( http_app_new )
    ( http_app_quiet a )
    ( http_app_idle_ms a 20000 )
    ( http_app_workers a 4 )
    ( http_app_get a `/fast` \ HttpRequest req Params p → HttpResponse { ^ ( response_text 200 `fast\n` ) } )
    ( http_app_get a `/slow` \ HttpRequest req Params p → HttpResponse {
        = slow_started T
        ( wait_for \ → b { ^ idle_gone } )
        ^ ( response_text 200 `slow\n` )
    } )
    : ( @ v ) c \ → v { ( ctl 18995 ) }
    : !Thread ThreadErr ct ( thread_spawn c )
    : i rc ( http_app_listen a `127.0.0.1` 18995 )
    ?? ct { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_print `rc=` ) ( nurl_print ( nurl_str_int rc ) )
    ( nurl_print ` in-flight-200=` ) ( nurl_print ? slow_ok `T` `F` )
    ( nurl_print ` with-close=` ) ( nurl_print ? slow_close `T` `F` )
    ( nurl_print ` idle-closed-promptly=` ) ( nurl_println ? & >= idle_eof_ms 0 < idle_eof_ms 1000 `T` `F` )
    ^ 0
}
