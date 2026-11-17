// owned_string_sent_on_a_channel_runs_clean: an owned String sent on a `( Channel String )`
// AGORA-812 guard: accepted - the value owns its data
// map: §6.5 | A3 | runs-clean | - | AGORA-812
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`

@ main → i {
    : ( Channel String ) ch ( chan_new [String] )
    : !Thread ThreadErr t ( thread_spawn \ → v { ?? ( chan_recv [String] ch ) { T x → { ( nurl_println ( string_data x ) ) } F → {} } } )
    ( chan_send [String] ch ( string_from `an owned message on the heap, long enough to matter` ) )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
