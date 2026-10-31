// chan_send_then_use: a String sent on a channel, then used by the sender.
// map: §6.5 | A3 | rejected | h21 | String sent on channel then read by sender after receiver freed it
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
