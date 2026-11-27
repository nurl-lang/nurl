// A channel made by a function and handed back.
$ `stdlib/std/channel.nu`

@ make → ( Channel i ) { ^ ( chan_new [i] ) }

@ main → i {
    : ( Channel i ) ch ( make )
    ( chan_send [i] ch 3 )
    : ?i got ( chan_recv [i] ch )
    : i r ?? got { T v → v F → 0 }
    ( chan_close [i] ch )
    ^ r
}
