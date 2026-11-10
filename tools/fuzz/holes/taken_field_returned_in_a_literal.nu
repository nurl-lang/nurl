// taken_field_returned_in_a_literal: `^ @ Holder { . h buf }` after a `sink` took the field: the literal held the emptied String, and the caller pushed to it
// main: accepted; a literal's field that is a field path recorded no read of the path (UBSan: null pointer passed to memcpy).
// map: §2.1 | A2 | rejected | - | agora #351: `^ @ Holder { . h buf }` after a `sink` took the field: the literal held the emptied String, and the caller pushed to it
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ f → Holder {
    : Holder h @ Holder { ( string_from `abc` ) }
    : i n ( take . h buf )
    ^ @ Holder { . h buf }
}

@ main → i {
    : Holder g ( f )
    ( string_push_str . g buf `x` )
    ( nurl_println ( string_data . g buf ) )
    ^ 0
}
