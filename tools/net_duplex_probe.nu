// Exercise prepared TLS records and retained partial ciphertext against an
// independent SSL MemoryBIO peer; no read or write operation may park alone.
$ `stdlib/std/net.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/async.nu`

: ~ i duplex_port 0
: ~ i duplex_result 2

@ duplex_run → i {
    : TcpConn conn ?? ( tcp_connect_tls `127.0.0.1` duplex_port `localhost` 0 ) {
        T value → value
        F error → { ( nurl_eprintln ( net_err_name error ) ) ^ 2 }
    }
    : ( Vec u ) payload ( vec_with_cap [u] 4194304 )
    : b sized ( vec_set_len [u] payload 4194304 )
    ( nurl_memset ( vec_data [u] payload ) 65 4194304 )
    : !( Vec u ) NetErr prepared ( tcp_prepare_write conn payload )
    ( vec_free [u] payload )
    : ~ i status 0
    ?? prepared {
        F error → { ( nurl_eprintln ( net_err_name error ) ) = status 2 }
        T wire → {
            : ( Vec u ) received ( vec_new [u] )
            : ~ i sent 0
            : i end + ( monotonic_ns ) 3000000000
            ( tcp_set_write_deadline conn end )
            ~ & == status 0 | < sent ( vec_len [u] wire ) < ( vec_len [u] received ) 13 {
                ? >= ( monotonic_ns ) end { = status 1 } {}
                : ~ i progress 0
                ?? ( tcp_try_read_into conn received 16384 ) {
                    T count → { = progress + progress count }
                    F error → { ( nurl_eprintln ( net_err_name error ) ) = status 1 }
                }
                ? < sent ( vec_len [u] wire ) {
                    ?? ( tcp_try_write_wire conn wire sent ) {
                        T count → { = sent + sent count = progress + progress count }
                        F error → { ( nurl_eprintln ( net_err_name error ) ) = status 1 }
                    }
                } {}
                ? & == status 0 == progress 0 {
                    : i ready ( tcp_wait_io conn T < sent ( vec_len [u] wire ) 100 )
                    ? < ready 0 { = status 1 } {}
                } {}
            }
            : ( Vec u ) expected ( bytes_from_str `hello partial` )
            ? ! ( bytes_eq received expected ) { = status 1 } {}
            ( vec_free [u] expected )
            ( vec_free [u] received )
            ( vec_free [u] wire )
        }
    }
    ( tcp_close_conn conn )
    ^ status
}

@ main → i {
    ? != ( nurl_argv_count ) 3 { ^ 2 } {}
    : s port ( nurl_argv_get 1 )
    : s asynchronous ( nurl_argv_get 2 )
    = duplex_port ( nurl_str_to_int port )
    : b async != 0 ( nurl_str_to_int asynchronous )
    ? async {
        ( runtime_init 1 )
        : Fiber worker ( spawn_owned \ → v { = duplex_result ( duplex_run ) } )
        ( runtime_run )
        ( runtime_shutdown )
    } { = duplex_result ( duplex_run ) }
    ^ duplex_result
}
