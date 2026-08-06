// sleep_in_main.nu — a sleep in the main context must not stop the world.
//
// On a cooperative runtime — the freestanding one, where every "thread"
// is a coroutine on one vCPU — `sleep_ms` in main used to be a plain
// nanosleep. That is not a wait, it is a freeze: the server this program
// spawns never ran, never bound its port, and the connect below was
// refused by a machine that was merely asleep.
//
// The shape is ordinary enough to be a habit: spawn a worker, give it a
// moment, then talk to it.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ serve → v {
    ?? ( tcp_listen `127.0.0.1` 19701 ) {
        F _e → ( nurl_print `listen failed\n` )
        T l → {
            ?? ( tcp_accept l ) {
                F _e → ( nurl_print `accept failed\n` )
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
    // The server has not run yet; this sleep is its only chance to.
    ( sleep_ms 200 )
    ?? ( tcp_connect `127.0.0.1` 19701 ) {
        F e → {
            ( nurl_print `connect failed: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
        }
        T c → {
            ?? ( tcp_read_chunk c 16 ) {
                T got → {
                    ( nurl_print `the server ran while main slept: ` )
                    ( nurl_print ? == ( vec_len [u] got ) 4 `YES\n` `NO\n` )
                    ( vec_free [u] got )
                }
                F _e → ( nurl_print `read failed\n` )
            }
            ( tcp_close_conn c )
        }
    }
    ?? t { T th → { : i _j ( thread_join th ) } F _e → {} }
    ^ 0
}
