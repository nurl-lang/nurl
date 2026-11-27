// A receive that does not wait, on a channel nothing was sent on: None.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) ch ( chan_new [i] )
    : ?i got ( chan_try_recv [i] ch )
    : i r ?? got { T v → v F → 0 }
    ( chan_close [i] ch )
    ^ r
}
