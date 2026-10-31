// net_bulk_no_stall.nu — a bulk send from a server thread to the main
// thread over loopback takes as long as its bytes take, not as long as a
// timer.
//
// The server writes 1 MB in 64 KB pieces and closes. The client reads to
// the end, checks every byte, and times the stream from its connect.
// Hosted, the kernel's TCP moves it in milliseconds. With no libc
// (unikernel/run_nolibc_tests.sh) both ends are coroutines on one OS
// thread, and the NURL socket layer (unikernel/net/sockets.nu) is the
// TCP. There a socket wait once blocked while its own drive still had
// frames queued (Agora #143). Each window then slept until the sender's
// retransmit deadline, and each RTT sample held that sleep, so the next
// deadline grew 1.6×: 10.7 s for this megabyte, against 19 ms. The bound
// is one second: fifty times the run, a tenth of the stall.
// requires: live fibers

// Port 18797, unique across the corpus.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

: ~ i sent -1

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

// Byte k of the stream: a pattern that no piece, segment or window
// boundary lines up with.
@ byte_at i k → u { ^ # u & ^^ * k 31 >> k 9 255 }

@ serve TcpListener l i total → v {
    ?? ( tcp_accept l ) {
        T c → {
            : ( Vec u ) piece ( vec_with_cap [u] 65536 )
            : ~ i off 0
            : ~ b ok T
            ~ && ok < off total {
                ( vec_clear [u] piece )
                : i n ? < - total off 65536 - total off 65536
                : ~ i k 0
                ~ < k n { ( vec_push [u] piece ( byte_at + off k ) ) = k + k 1 }
                ?? ( tcp_write_all c piece ) { T _ → { = off + off n } F _ → { = ok F } }
            }
            = sent off
            ( tcp_close_conn c )
        }
        F _ → {}
    }
}

@ main → i {
    : i total 1048576
    ?? ( tcp_listen `127.0.0.1` 18797 ) {
        T l → {
            : ( @ v ) server \ → v { ( serve l total ) }
            : !Thread ThreadErr st ( thread_spawn server )
            ?? st {
                T t → {
                    : i t0 ( monotonic_ns )
                    ?? ( tcp_connect `127.0.0.1` 18797 ) {
                        T c → {
                            : ( Vec u ) buf ( vec_with_cap [u] 65536 )
                            : ~ i got 0
                            : ~ b same T
                            : ~ b more T
                            ~ more {
                                ( vec_clear [u] buf )
                                ?? ( tcp_read_into c buf 65536 ) {
                                    T n → {
                                        : ~ i k 0
                                        ~ < k n {
                                            ? != ( vec_at [u] buf k ) ( byte_at + got k ) { = same F } {}
                                            = k + k 1
                                        }
                                        = got + got n
                                    }
                                    F _ → { = more F }
                                }
                            }
                            : i ms ( elapsed_ms_since t0 )
                            ( tcp_close_conn c )
                            ( thread_join t )
                            ( label `bytes` ? && same == got total `ok` `FAIL` )
                            ( label `sent` ? == sent total `ok` `FAIL` )
                            ? < ms 1000 { ( label `in_time` `ok` ) } {
                                ( nurl_print `in_time=FAIL ` ) ( nurl_print_int ms ) ( nurl_print ` ms\n` )
                            }
                        }
                        F _ → { ( label `connect` `FAIL` ) ( thread_join t ) }
                    }
                }
                F _ → { ( label `spawn` `FAIL` ) }
            }
            ( tcp_close_listener l )
        }
        F _ → { ( label `listen` `FAIL` ) }
    }
    ^ 0
}
