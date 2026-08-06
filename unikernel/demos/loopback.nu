// unikernel/demos/loopback.nu — 127.0.0.1 on a machine that also has an
// interface.
//
// Every other network demo here talks to the outside. This one talks to
// itself while an interface is up, which is a different code path and
// was a broken one: the stack had no way to say what address a datagram
// was sent FROM, so a reply to something addressed to 127.0.0.1 went out
// with the interface's address in its header. The receiver — the same
// machine — then computed the TCP checksum over a different
// pseudo-header, decided the segment was corrupt, and dropped it. No
// counter moved; a connection to 127.0.0.1 simply never completed.
//
// It matters because that is how a node made of parts talks to itself: a
// relay, a worker and a control endpoint in one program, meeting on
// loopback. Nothing in the hosted corpus can catch it — a hosted program
// uses the kernel's loopback — and nothing in the guest gate did either,
// because every other demo has exactly one endpoint.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ serve → v {
    ?? ( tcp_listen `0.0.0.0` 19700 ) {
        F e → {
            ( nurl_print `listen failed: ` ) ( nurl_print ( net_err_name e ) ) ( nurl_print `\n` )
        }
        T l → {
            ( nurl_print `listening on 19700\n` )
            ?? ( tcp_accept l ) {
                F e → {
                    ( nurl_print `accept failed: ` ) ( nurl_print ( net_err_name e ) ) ( nurl_print `\n` )
                }
                T c → {
                    : !v NetErr w ( tcp_write_str c `pong` )
                    ?? w { T _ → {} F _e → {} }
                    ( tcp_close_conn c )
                }
            }
            ( tcp_close_listener l )
        }
    }
}

@ main → i {
    : !Thread ThreadErr t ( thread_spawn \ → v { ( serve ) } )
    ( sleep_ms 300 )
    ?? ( tcp_connect `127.0.0.1` 19700 ) {
        F e → {
            ( nurl_print `connect failed: ` ) ( nurl_print ( net_err_name e ) ) ( nurl_print `\n` )
        }
        T c → {
            ?? ( tcp_read_chunk c 16 ) {
                T got → {
                    ( nurl_print `loopback round trip: ` )
                    ( nurl_print ? == ( vec_len [u] got ) 4 `YES\n` `NO\n` )
                    ( vec_free [u] got )
                }
                F e → {
                    ( nurl_print `read failed: ` ) ( nurl_print ( net_err_name e ) ) ( nurl_print `\n` )
                }
            }
            ( tcp_close_conn c )
        }
    }
    ?? t { T th → { : i _j ( thread_join th ) } F _e → {} }
    ^ 0
}
