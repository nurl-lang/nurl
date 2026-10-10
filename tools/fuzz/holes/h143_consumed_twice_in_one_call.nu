// H143: one String passed to a `sink` parameter and to a borrowed one of the same call: moves were flushed only after the statement, so the later argument read what the first gave away (use after free).
$ `stdlib/core/string.nu`

@ f sink String x String y → i { : i n ( string_len x ) ( string_free x ) ^ + n ( string_len y ) }

@ main → i {
    : String m ( string_from `abcd` )
    ( nurl_println_int ( f m m ) )
    ( nurl_println `P2B-MARK` )
    ^ 0
}
