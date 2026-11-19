// map: §6.5 | A3 | rejected | - | agora #812: `( chan_send [s] ch ( string_data m ) )` to a receiving thread, then m freed
// AGORA-812: refused - a value chan_send hands to whichever thread receives it may not view this side's storage, as a spawned closure's may not (A3 SpawnOK; main f9356928: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`

@ main → i {
    : String m ( string_from `a message on the heap, long enough to matter, surely` )
    : ( Channel s ) ch ( chan_new [s] )
    : !Thread ThreadErr t ( thread_spawn \ → v { ?? ( chan_recv [s] ch ) { T x → { ( sleep_ms 50 ) ( nurl_println x ) } F → {} } } )
    ( chan_send [s] ch ( string_data m ) )
    ( string_free m )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
