// taken_field_returned_itself: `^ . h buf` after a `sink` took the field: the caller got the emptied String back and pushed to it
// main: accepted; the `ret` row named only `h`, so the read of the taken field went unasked (UBSan: null pointer passed to memcpy).
// map: §2.1 | A2 | rejected | - | agora #351: `^ . h buf` after a `sink` took the field: the caller got the emptied String back and pushed to it
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ f → String {
    : Holder h @ Holder { ( string_from `abc` ) }
    : i n ( take . h buf )
    ^ . h buf
}

@ main → i {
    : String v ( f )
    ( string_push_str v `x` )
    ( nurl_println ( string_data v ) )
    ^ 0
}
