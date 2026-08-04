// unixsock.nu — std/unixsock.nu acceptance.
//
// The deterministic core uses socketpair() — a pure syscall, no path /
// bind / listen / accept / thread — to exercise the read/write/close
// path both directions. The full listen+accept+connect round-trip runs
// a server thread over a /tmp socket — hence `requires: live`, the same
// declaration the TCP/websocket live tests carry.
// requires: live

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/unixsock.nu`
$ `stdlib/std/thread.nu`

@ str_to_vec s in → ( Vec u ) {
    : i n ( nurl_str_len in )
    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] out # u ( nurl_str_get in k ) ) = k + k 1 }
    ^ out
}

@ vec_to_str ( Vec u ) v → String {
    : i n ( vec_len [u] v )
    : *u p ( vec_data [u] v )
    : String out ( string_with_cap + n 1 )
    : ~ i k 0
    ~ < k n { ( string_push_char out # i . p k ) = k + k 1 }
    ^ out
}

@ main → i {
    // ── error name table ──
    ( nurl_print `err_names=` )
    ( nurl_print ( unix_err_name # UnixErr UnixBind ) ) ( nurl_print `,` )
    ( nurl_print ( unix_err_name # UnixErr UnixAddrInUse ) ) ( nurl_print `,` )
    ( nurl_print ( unix_err_name # UnixErr UnixConnect ) ) ( nurl_print `\n` )

    // ── socketpair round-trip (deterministic) ──
    : !UnixPair UnixErr pr ( unix_socketpair )
    ?? pr {
        T pair → {
            : UnixConn a . pair a
            : UnixConn b . pair b
            // a → b
            : ( Vec u ) msg ( str_to_vec `ping` )
            : !v UnixErr wr ( unix_write_all a msg )
            ?? wr { T _ → {} F e → { ( nurl_print `write FAILED ` ) ( nurl_print ( unix_err_name # UnixErr e ) ) ( nurl_print `\n` ) } }
            ( vec_free [u] msg )
            : !( Vec u ) UnixErr rd ( unix_read_chunk b 64 )
            ?? rd {
                T got → {
                    : String s ( vec_to_str got )
                    ( nurl_print `pair a→b: ` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
                    ( string_free s ) ( vec_free [u] got )
                }
                F _ → ( nurl_print `read FAILED\n` )
            }
            // b → a (other direction)
            : ( Vec u ) msg2 ( str_to_vec `pong!` )
            : !v UnixErr wr2 ( unix_write_all b msg2 )
            ?? wr2 { T _ → {} F _ → {} }
            ( vec_free [u] msg2 )
            : !( Vec u ) UnixErr rd2 ( unix_read_chunk a 64 )
            ?? rd2 {
                T got → {
                    : String s ( vec_to_str got )
                    ( nurl_print `pair b→a: ` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
                    ( string_free s ) ( vec_free [u] got )
                }
                F _ → ( nurl_print `read2 FAILED\n` )
            }
            // close one end, read on the other → EOF (empty Vec)
            ( unix_close_conn a )
            : !( Vec u ) UnixErr eofr ( unix_read_chunk b 64 )
            ?? eofr {
                T got → {
                    ( nurl_print `pair eof_after_close: ` )
                    ( nurl_print ? == 0 ( vec_len [u] got ) `T` `F` ) ( nurl_print `\n` )
                    ( vec_free [u] got )
                }
                F _ → ( nurl_print `eof read err\n` )
            }
            ( unix_close_conn b )
        }
        F e → { ( nurl_print `socketpair FAILED ` ) ( nurl_print ( unix_err_name # UnixErr e ) ) ( nurl_print `\n` ) }
    }

    // ── full listen/accept/connect round-trip (gated) ──
    ( __live_roundtrip )
    ^ 0
}

// Server thread reads one chunk and echoes it back, then closes.
: ~ i g_srv_path 0  // sym handle carrying the socket path to the thread
: ~ i g_done 0

@ __live_roundtrip → v {
    : String path ( string_with_cap 48 )
    ( string_push_str path `/tmp/nurl_unixsock_` )
    ( string_push_str path ( nurl_str_int ( getpid ) ) )
    ( string_push_str path `.sock` )
    : !UnixListener UnixErr lr ( unix_listen ( string_data path ) )
    ?? lr {
        T listener → {
            // server fiber: accept one conn, echo a chunk
            : ( @ v ) server_fn \ → v {
                : !UnixConn UnixErr ar ( unix_accept listener )
                ?? ar {
                    T conn → {
                        : !( Vec u ) UnixErr rd ( unix_read_chunk conn 64 )
                        ?? rd { T got → { : !v UnixErr _w ( unix_write_all conn got ) ?? _w { T _ → {} F _ → {} } ( vec_free [u] got ) } F _ → {} }
                        ( unix_close_conn conn )
                    }
                    F _ → {}
                }
            }
            : !Thread ThreadErr st ( thread_spawn server_fn )
            ?? st {
                T th → {
                    : !UnixConn UnixErr cr ( unix_connect ( string_data path ) )
                    ?? cr {
                        T client → {
                            : ( Vec u ) msg ( str_to_vec `hello-unix` )
                            : !v UnixErr _w ( unix_write_all client msg )
                            ?? _w { T _ → {} F _ → {} }
                            ( vec_free [u] msg )
                            : !( Vec u ) UnixErr echo ( unix_read_chunk client 64 )
                            ?? echo {
                                T got → { : String s ( vec_to_str got ) ( nurl_print `live echo: ` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) ( string_free s ) ( vec_free [u] got ) }
                                F _ → ( nurl_print `live echo err\n` )
                            }
                            ( unix_close_conn client )
                        }
                        F _ → ( nurl_print `live connect err\n` )
                    }
                    : i _j ( thread_join th )
                }
                F _ → ( nurl_print `live thread spawn err\n` )
            }
            ( unix_close_listener listener )
        }
        F _ → ( nurl_print `live listen err\n` )
    }
    ( string_free path )
}
