$ `stdlib/core/string.nu`
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel String ) ch ( chan_new [String] )
    : String s ( string_from `a message long enough for a heap buffer` )
    ( chan_send [String] ch s )
    : ?String got ( chan_recv [String] ch )
    ( chan_close [String] ch )
    ^ 0
}
