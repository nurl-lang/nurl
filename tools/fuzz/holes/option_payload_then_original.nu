// option_payload_then_original: a String moved into an Option, Option consumed, original name read.
// map: §2.1 | A2 | rejected | h16 | String moved into Option payload, consumed, original read
$ `stdlib/core/string.nu`

@ eat ? String o → v { ?? o { T s → { ( string_free s ) } F → {} } }

@ main → i {
    : String s ( string_from `another long heap allocated string value` )
    ( eat @ ?String { T s } )
    ( nurl_println ( string_data s ) )
    ^ 0
}
