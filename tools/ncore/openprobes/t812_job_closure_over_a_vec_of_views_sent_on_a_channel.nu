// map: §6.5 | A3 | rejected | - | agora #812: a Job closure over a `( Vec s )` viewing a local String, sent on a `( Channel Job )` to a worker, then the String freed
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`

: Job { ( @ v ) run }

@ main → i {
    : String m ( string_from `a message on the heap, long enough to matter, surely` )
    : ( Channel Job ) ch ( chan_new [Job] )
    : !Thread ThreadErr t ( thread_spawn \ → v { ?? ( chan_recv [Job] ch ) { T j → { ( sleep_ms 50 ) : ( @ v ) g . j run ( g ) } F → {} } } )
    : ( Vec s ) vs ( vec_new [s] )
    ( vec_push [s] vs ( string_data m ) )
    ( chan_send [Job] ch @ Job { \ → v { ( nurl_println ( vec_at [s] vs 0 ) ) } } )
    ( string_free m )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
