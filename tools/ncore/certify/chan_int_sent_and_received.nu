$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) ch ( chan_new [i] )
    ( chan_send [i] ch 41 )
    : ?i got ( chan_recv [i] ch )
    : i r ?? got { T v → v F → 0 }
    ( chan_close [i] ch )
    ^ + r 1
}
