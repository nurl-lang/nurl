// H16: a String moved into an Option, Option consumed, original name read.
$ `stdlib/core/string.nu`

@ eat ? String o → v { ?? o { T s → { ( string_free s ) } F → {} } }

@ main → i {
    : String s ( string_from `another long heap allocated string value` )
    ( eat @ ?String { T s } )
    ( nurl_println ( string_data s ) )
    ^ 0
}
