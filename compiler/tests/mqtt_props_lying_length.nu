// mqtt_props_lying_length.nu — a property block whose last property's
// length bytes lie past the packet end. `_mqtt_byte` reads -1 there, so
// the old walk stepped `2 + (-1 * 256 + -1)` = 255 bytes back: from
// the string property (id 3) at byte 254 to the start of the block, which
// it walked again, for ever. The client's receive loop hung on one packet
// from a broker. The walk now ends at the packet's end and only moves
// forward (found in the stdlib hole hunt of 2026-10-28).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/pair.nu`
$ `stdlib/ext/mqtt.nu`

@ main → i {
    : ( Vec u ) pkt ( vec_new [u] )
    : ~ i k 0
    // 127 one-byte properties (id 1, Payload Format Indicator)
    ~ < k 127 { ( vec_push [u] pkt # u 1 ) ( vec_push [u] pkt # u 0 ) = k + k 1 }
    // a string property (id 3, Content Type) with no length bytes left
    ( vec_push [u] pkt # u 3 )
    : ( Vec ( Pair String String ) ) out ( vec_new [( Pair String String )] )
    ( _mqtt_parse_props pkt 0 ( vec_len [u] pkt ) out )
    ( nurl_println ( nurl_str_cat `user properties: ` ( nurl_str_int ( vec_len [( Pair String String )] out ) ) ) )
    // a user property (id 38) whose key length runs past the end
    : ( Vec u ) p2 ( vec_new [u] )
    ( vec_push [u] p2 # u 38 ) ( vec_push [u] p2 # u 255 )
    : ( Vec ( Pair String String ) ) out2 ( vec_new [( Pair String String )] )
    ( _mqtt_parse_props p2 0 100 out2 )
    ( nurl_println ( nurl_str_cat `user properties: ` ( nurl_str_int ( vec_len [( Pair String String )] out2 ) ) ) )
    ^ 0
}
