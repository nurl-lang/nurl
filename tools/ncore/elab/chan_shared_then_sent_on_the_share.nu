// A second share of a channel: sent on through one, received through the
// other.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) a ( chan_new [i] )
    : ( Channel i ) b ( Channel_share [i] a )
    ( chan_send [i] b 9 )
    : ?i got ( chan_recv [i] a )
    : i r ?? got { T v → v F → 0 }
    ( chan_close [i] a )
    ^ r
}
