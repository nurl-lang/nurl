// Socket/TLS backpressure deadline driver for test_net_write_deadline.py.
$ `stdlib/std/net.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/time.nu`

: ~ i deadline_port 0
: ~ i deadline_mode 0
: ~ i deadline_result 2

@ deadline_write TcpConn conn i mode ( Vec u ) payload → i {
    : i raw ( tcp_conn_fd conn )
    : *u data ( vec_data [u] payload )
    : i size ( vec_len [u] payload )
    ? < mode 2 {
        : i sent ? == mode 0 ( nurl_tcp_write raw # s data size )
        ( nurl_tcp_write2 raw # s data / size 2 # s + # i data / size 2 / size 2 )
        : i error ( nurl_tcp_err_kind raw )
        ? & < sent size == error 7 { ^ 0 } {}
        ( nurl_eprint `raw write did not time out: ` )
        ( nurl_eprintln ( nurl_str_int error ) )
        ^ 1
    } {}
    : !v NetErr result ? | == mode 3 == mode 5
    ( tcp_write_all2 conn payload payload ) ( tcp_write_all conn payload )
    ?? result {
        T _ → { ( nurl_eprintln `unexpected complete write` ) ^ 1 }
        F error → {
            ?? error { NetTimeout → { ^ 0 } _ → {} }
            ( nurl_eprintln ( net_err_name error ) )
            ^ 1
        }
    }
}

@ deadline_run → i {
    : !TcpConn NetErr connected ? >= deadline_mode 4
    ( tcp_connect_tls `127.0.0.1` deadline_port `localhost` 0 )
    ( tcp_connect `127.0.0.1` deadline_port )
    ?? connected {
        F error → { ( nurl_eprintln ( net_err_name error ) ) ^ 2 }
        T conn → {
            : ( Vec u ) payload ( vec_with_cap [u] 16777216 )
            : b sized ( vec_set_len [u] payload 16777216 )
            ( nurl_memset ( vec_data [u] payload ) 65 16777216 )
            ( tcp_set_timeout conn 2000 )
            : i start ( monotonic_ns )
            : i limit + start 100000000
            ( tcp_set_write_deadline conn limit )
            : i result ? == ( tcp_write_deadline conn ) limit
            ( deadline_write conn deadline_mode payload ) 2
            : i elapsed / - ( monotonic_ns ) start 1000000
            ( nurl_print_int elapsed )
            ( tcp_set_write_deadline conn 0 )
            ( vec_free [u] payload )
            ( tcp_close_conn conn )
            ^ result
        }
    }
}

@ main → i {
    ? != ( nurl_argv_count ) 4 { ^ 2 } {}
    : s port ( nurl_argv_get 1 )
    : s mode ( nurl_argv_get 2 )
    : s asynchronous ( nurl_argv_get 3 )
    = deadline_port ( nurl_str_to_int port )
    = deadline_mode ( nurl_str_to_int mode )
    : b async != 0 ( nurl_str_to_int asynchronous )
    ? async {
        ( runtime_init 1 )
        : Fiber worker ( spawn_owned \ → v { = deadline_result ( deadline_run ) } )
        ( runtime_run )
        ( runtime_shutdown )
    } { = deadline_result ( deadline_run ) }
    ^ deadline_result
}
