// literal_view_sent_on_a_channel_runs_clean: a string literal (static storage) sent on a `( Channel s )`
// AGORA-812 guard: accepted - a literal's view is static
// map: §6.5 | A3 | runs-clean | - | AGORA-812
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`

@ main → i {
    : ( Channel s ) ch ( chan_new [s] )
    : !Thread ThreadErr t ( thread_spawn \ → v { ?? ( chan_recv [s] ch ) { T x → { ( nurl_println x ) } F → {} } } )
    ( chan_send [s] ch `a literal: static storage` )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
