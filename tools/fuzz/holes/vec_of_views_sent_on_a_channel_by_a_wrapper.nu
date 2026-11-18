// vec_of_views_sent_on_a_channel_by_a_wrapper: `( sendit ch vs )`, sendit sending its `( Vec s )` parameter on a channel to a receiving thread, vs viewing m
// AGORA-812 (CodeRabbit on github#1942): refused - a function that sends its parameter on makes its callers' arguments cross (main: accepted, heap-use-after-free)
// map: §6.5 | A3 | rejected | - | AGORA-812
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`

@ sendit ( Channel ( Vec s ) ) ch ( Vec s ) xs → v { ( chan_send [( Vec s )] ch xs ) }

@ main → i {
    : String m ( string_from `a message on the heap, long enough to matter` )
    : ~ ( Vec s ) vs ( vec_new [s] )
    ( vec_push [s] vs ( string_data m ) )
    : ( Channel ( Vec s ) ) ch ( chan_new [( Vec s )] )
    : !Thread ThreadErr t ( thread_spawn \ → v { ?? ( chan_recv [( Vec s )] ch ) { T x → { ( sleep_ms 50 ) ( nurl_println ( vec_at [s] x 0 ) ) } F → {} } } )
    ( sendit ch vs )
    ( string_free m )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
