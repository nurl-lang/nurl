// should_fail_ts_factory_cycle.nu — what a closure captures travels through
// the function that builds it, also one compiled after its caller: a job
// whose closure captures the channel it is queued on keeps that channel
// alive (docs/MEMORY.md §7.7).

$ `stdlib/std/channel.nu`

: Job { ( @ i ) run }

@ main → i {
    : ( Channel Job ) ch ( chan_new [Job] )
    ( chan_send [Job] ch ( make_job ch ) )
    ^ 0
}

@ make_job ( Channel Job ) ch → Job {
    : ( Channel Job ) mine ( Channel_share [Job] ch )
    ^ @ Job { \ → i { ^ ( chan_len [Job] mine ) } }
}
