// owned_raw_string_sent_on_a_channel: `: s x ( nurl_str_cat … )  ( chan_send [s] ch x )` in a callee that releases x on its way out, the receiver reading it later
// AGORA-812 (CodeRabbit on github#1942): refused by the walk and tools/ncore - a raw string binding that owns its buffer hands on a view of it
// map: §6.5 | A3 | rejected | - | AGORA-812
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`

@ send_one ( Channel s ) ch → v {
    : s x ( nurl_str_cat `an owned raw string on the heap, ` `long enough to matter` )
    ( chan_send [s] ch x )
}

@ main → i {
    : ( Channel s ) ch ( chan_new [s] )
    : !Thread ThreadErr t ( thread_spawn \ → v { ?? ( chan_recv [s] ch ) { T y → { ( sleep_ms 50 ) ( nurl_println y ) } F → {} } } )
    ( send_one ch )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
