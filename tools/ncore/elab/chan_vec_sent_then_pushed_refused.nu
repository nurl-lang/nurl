// A Vec pushed after it was sent: it moved into the queue. The checker
// refuses it.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel ( Vec i ) ) ch ( chan_new [( Vec i )] )
    : ( Vec i ) v ( vec_new [i] )
    ( chan_send [( Vec i )] ch v )
    ( vec_push [i] v 1 )
    ( chan_close [( Vec i )] ch )
    ^ 0
}
