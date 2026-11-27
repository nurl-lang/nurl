// A Vec of numbers sent on a channel and received: the Vec moves into the
// queue and out of it again.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel ( Vec i ) ) ch ( chan_new [( Vec i )] )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ( chan_send [( Vec i )] ch v )
    : ?( Vec i ) got ( chan_recv [( Vec i )] ch )
    : i n ?? got { T w → ( vec_len [i] w ) F → 0 }
    ( chan_close [( Vec i )] ch )
    ^ n
}
