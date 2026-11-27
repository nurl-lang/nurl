// Numbers sent in one loop and received in another.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) ch ( chan_new [i] )
    : ~ i k 0
    ~ < k 3 {
        ( chan_send [i] ch k )
        = k + k 1
    }
    : ~ i s 0
    = k 0
    ~ < k 3 {
        : ?i got ( chan_recv [i] ch )
        = s + s ?? got { T v → v F → 0 }
        = k + k 1
    }
    ( chan_close [i] ch )
    ^ s
}
