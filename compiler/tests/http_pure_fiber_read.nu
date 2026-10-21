// http_pure_fiber_read.nu — the pure HTTP client's plaintext transport
// must not hold its fiber's worker while it waits for the server.
//
// hp_conn_read_some on a plain connection issued one blocking
// nurl_tcp_read, so on a fiber a slow server stalled the whole worker
// and every fiber queued on it. On ONE worker, a client fiber writes a
// request and reads the reply of a server (an OS thread) that answers
// after 200 ms, while a second fiber ticks every 10 ms; the ticker must
// keep running throughout. A second connection, never answered, must
// end in the read deadline (hp_conn_set_timeout) — error -2 — on time,
// the deadline riding the netpoller.
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/http_pure.nu`

: ~ i ticks 0
: ~ i stop 0

@ __port TcpListener l → i {
    : String address ( tcp_local_addr l )
    : ~ i port 0
    : ~ i k 0
    ~ < k ( string_len address ) {
        : i ch ( string_get address k )
        ? == ch 58 { = port 0 } { ? & >= ch 48 <= ch 57 { = port + * port 10 - ch 48 } {} }
        = k + k 1
    }
    ( string_free address )
    ^ port
}

@ __say s label s v → v {
    ( nurl_print label )
    ( nurl_print v )
    ( nurl_print `\n` )
}

// Connection 1: read the request, answer 200 ms later. Connection 2:
// read the request, answer nothing, hang up after 800 ms.
@ __serve TcpListener l → v {
    ?? ( tcp_accept l ) {
        T c → {
            ?? ( tcp_read_chunk c 256 ) { T v → ( vec_free [u] v ) F _ → {} }
            ( sleep_ms 200 )
            : !v NetErr w ( tcp_write_str c `hello` )
            ( tcp_close_conn c )
        }
        F _ → {}
    }
    ?? ( tcp_accept l ) {
        T c → {
            ?? ( tcp_read_chunk c 256 ) { T v → ( vec_free [u] v ) F _ → {} }
            ( sleep_ms 800 )
            ( tcp_close_conn c )
        }
        F _ → {}
    }
}

@ __request i port → !HttpConn i {
    ?? ( hp_conn_open 0 `127.0.0.1` port `` 0 ) {
        F e → ^ @ !HttpConn i { F e }
        T c → {
            : ( Vec u ) req ( bytes_from_str `GET / HTTP/1.1\r\n\r\n` )
            ( __say `write=` ( nurl_str_int ( hp_conn_write c req ) ) )
            ^ @ !HttpConn i { T c }
        }
    }
}

@ main → i {
    ( runtime_init 1 )
    : TcpListener l ?? ( tcp_listen `127.0.0.1` 0 ) { T x → x F _ → { ^ 1 } }
    : i port ( __port l )
    : ( @ v ) server \ → v { ( __serve l ) }
    : !Thread ThreadErr st ( thread_spawn server )

    : ( @ v ) ticker \ → v {
        ~ == stop 0 {
            ( sleep_ms 10 )
            = ticks + ticks 1
        }
    }
    : ( @ v ) client \ → v {
        : HttpConn c ?? ( __request port ) { T x → x F _ → { = stop 1 ^ v } }
        : ( Vec u ) acc ( vec_new [u] )
        : i before ticks
        : i r ( hp_conn_read_some c acc )
        : i during - ticks before
        ( __say `read=` ( nurl_str_int r ) )
        : String body ( bytes_to_str acc )
        ( __say `body=` ( string_data body ) )
        ( __say `ticker_ran_during_read=` ? >= during 5 `yes` `no` )
        ( hp_conn_close c )

        : HttpConn c2 ?? ( __request port ) { T x → x F _ → { = stop 1 ^ v } }
        ( hp_conn_set_timeout c2 100 )
        : ( Vec u ) acc2 ( vec_new [u] )
        : i t0 ( monotonic_ns )
        : i r2 ( hp_conn_read_some c2 acc2 )
        : i ms ( elapsed_ms_since t0 )
        ( __say `deadline_read=` ( nurl_str_int r2 ) )
        ( __say `deadline_on_time=` ? & >= ms 80 < ms 700 `yes` `no` )
        ( hp_conn_close c2 )
        = stop 1
    }
    ( spawn ticker )
    ( spawn client )
    ( runtime_run )
    ( runtime_shutdown )
    ?? st { T t → ( thread_join t ) F _ → {} }
    ^ 0
}
