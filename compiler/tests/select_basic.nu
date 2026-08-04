// select_basic.nu — acceptance test for the `?? { }` channel-select
// construct (Go-style select over channels).
//
// The deterministic single-threaded cases (default arm, value-ready arm,
// closed-channel arm, case priority) need nothing from the OS. The
// blocking path — a producer thread waking a parked selector — spawns a
// real thread, hence `requires: live`. Its output is deterministic
// because the selector cannot proceed until the producer has sent.
// requires: live

$ `stdlib/std/channel.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/string.nu`

@ run_blocking_test → v {
    : ( Channel i ) ints ( chan_new [i] )
    : ( Channel String ) strs ( chan_new [String] )
    // Producer sends a String; the selector below blocks until it lands.
    : ( @ v ) prod \ → v { ( chan_send [String] strs ( string_from `hi` ) ) }
    : !Thread ThreadErr r ( thread_spawn prod )
    ?? r {
        T t → {
            ?? {
                [i] ints → oi {
                    ?? oi { T v → { ( nurl_print `blk int=` ) ( nurl_print_int v ) } F → { ( nurl_print `blk ints closed\n` ) } }
                }
                [String] strs → os {
                    ?? os { T s → { ( nurl_print `blk str=` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) ( string_free s ) } F → { ( nurl_print `blk strs closed\n` ) } }
                }
            }
            ( thread_join t )
        }
        F e → { ( nurl_print `spawn fail\n` ) }
    }
    // The producer has joined, so its heap-captured env is dead — release
    // it. `thread_spawn` borrows the env and never frees it (§7.4: an
    // escaped closure's env belongs to the consumer).
    : *u prod_env # *u prod 1
    ( nurl_free # s prod_env )
    ( chan_close [i] ints ) ( chan_close [String] strs )
    ( chan_free [i] ints ) ( chan_free [String] strs )
}

@ main → i {
    : ( Channel i ) ch ( chan_new [i] )

    // 1) empty channel + default → the default arm runs (non-blocking).
    ?? {
        [i] ch → o { ?? o { T v → { ( nurl_print `unexpected ` ) ( nurl_print_int v ) } F → { ( nurl_print `none\n` ) } } }
        _ → { ( nurl_print `default\n` ) }
    }

    // 2) a queued value → the channel arm wins, binding Some(v).
    ( chan_send [i] ch 7 )
    ?? {
        [i] ch → o { ?? o { T v → { ( nurl_print `got ` ) ( nurl_print_int v ) } F → { ( nurl_print `none\n` ) } } }
        _ → { ( nurl_print `default\n` ) }
    }

    // 3) case priority: both ready, the first listed case wins.
    : ( Channel i ) a ( chan_new [i] )
    : ( Channel i ) b ( chan_new [i] )
    ( chan_send [i] a 1 )
    ( chan_send [i] b 2 )
    ?? {
        [i] a → oa { ?? oa { T v → { ( nurl_print `prio a=` ) ( nurl_print_int v ) } F → {} } }
        [i] b → ob { ?? ob { T v → { ( nurl_print `prio b=` ) ( nurl_print_int v ) } F → {} } }
        _ → { ( nurl_print `prio default\n` ) }
    }
    ( chan_close [i] a ) ( chan_close [i] b )
    ( chan_free [i] a ) ( chan_free [i] b )

    // 4) closed + empty channel → recv yields None, the None branch runs.
    ( chan_close [i] ch )
    ?? {
        [i] ch → o { ?? o { T v → { ( nurl_print `v=` ) ( nurl_print_int v ) } F → { ( nurl_print `closed\n` ) } } }
        _ → { ( nurl_print `default\n` ) }
    }
    ( chan_free [i] ch )

    // 5) blocking path — concurrency-gated.
    ( run_blocking_test )
    ^ 0
}
