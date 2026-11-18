// vec_of_views_sent_on_a_channel_through_two_wrappers: `( outer ch vs )`, outer handing its parameter to sendit, which sends it
// AGORA-812: refused - the crossing goes up the chain of wrappers
// map: §6.5 | A3 | rejected | - | AGORA-812
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`

@ sendit ( Channel ( Vec s ) ) ch ( Vec s ) xs → v { ( chan_send [( Vec s )] ch xs ) }

@ outer ( Channel ( Vec s ) ) ch ( Vec s ) xs → v { ( sendit ch xs ) }

@ main → i {
    : String m ( string_from `a message on the heap, long enough to matter` )
    : ~ ( Vec s ) vs ( vec_new [s] )
    ( vec_push [s] vs ( string_data m ) )
    : ( Channel ( Vec s ) ) ch ( chan_new [( Vec s )] )
    : !Thread ThreadErr t ( thread_spawn \ → v { ?? ( chan_recv [( Vec s )] ch ) { T x → { ( sleep_ms 50 ) ( nurl_println ( vec_at [s] x 0 ) ) } F → {} } } )
    ( outer ch vs )
    ( string_free m )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
