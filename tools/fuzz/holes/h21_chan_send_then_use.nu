// H21: a String sent on a channel, then used by the sender.
$ `stdlib/core/string.nu`
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel String ) ch ( chan_new [String] )
    : String s ( string_from `message string on heap, long enough here` )
    : b _ok ( chan_send [String] ch s )
    ?? ( chan_recv [String] ch ) { T r → { ( string_free r ) } F → {} }
    ( nurl_println ( string_data s ) )
    ^ 0
}
