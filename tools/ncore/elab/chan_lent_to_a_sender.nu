// A channel lent to a function that sends on it.
$ `stdlib/std/channel.nu`

@ put ( Channel i ) ch i k → v { ( chan_send [i] ch k ) }

@ main → i {
    : ( Channel i ) ch ( chan_new [i] )
    ( put ch 5 )
    : ?i got ( chan_recv [i] ch )
    : i r ?? got { T v → v F → 0 }
    ( chan_close [i] ch )
    ^ r
}
