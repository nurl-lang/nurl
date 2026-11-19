// map: §6.5 | A3 | rejected | - | agora #812: a closure capturing a view of a local String, sent on a `( Channel ( @ v ) )` to a worker, then the String freed
// AGORA-812: refused - a value chan_send hands to whichever thread receives it may not view this side's storage, as a spawned closure's may not (A3 SpawnOK; main f9356928: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`

@ main → i {
    : String m ( string_from `a message on the heap, long enough to matter, surely` )
    : ( Channel ( @ v ) ) ch ( chan_new [( @ v )] )
    : !Thread ThreadErr t ( thread_spawn \ → v { ?? ( chan_recv [( @ v )] ch ) { T g → { ( sleep_ms 50 ) ( g ) } F → {} } } )
    : s w ( string_data m )
    ( chan_send [( @ v )] ch \ → v { ( nurl_println w ) } )
    ( string_free m )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
