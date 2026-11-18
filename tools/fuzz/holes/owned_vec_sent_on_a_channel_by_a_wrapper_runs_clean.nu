// owned_vec_sent_on_a_channel_by_a_wrapper_runs_clean: `( sendit ch vs )`, sendit sending its `( Vec String )` parameter on a channel; vs owns its Strings
// AGORA-812 guard: accepted - the value owns its data, so nothing it holds is this side's to release
// map: §6.5 | A3 | runs-clean | - | AGORA-812
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`

@ sendit ( Channel ( Vec String ) ) ch sink ( Vec String ) xs → v { ( chan_send [( Vec String )] ch xs ) }

@ main → i {
    : ~ ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an owned message on the heap, long enough to matter` ) )
    : ( Channel ( Vec String ) ) ch ( chan_new [( Vec String )] )
    : !Thread ThreadErr t ( thread_spawn \ → v { ?? ( chan_recv [( Vec String )] ch ) { T x → { ( nurl_println ( string_data ( vec_at [String] x 0 ) ) ) } F → {} } } )
    ( sendit ch vs )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
