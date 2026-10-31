// string_consume_view_of_string: string_adopt of a view takes the buffer over while its owner still holds it: released twice.
// Closed: in safe code only a declared `sink` takes a raw string over, and its callee releases it; a caller hands over a string it owns, or a copy of anything else (mem_sink_str_arg, __own_sink_str_params).
// ( string_adopt ( string_data b ) ): `a` and `b` both release "hello"'s buffer. ( string_adopt . r name ):
// `c` and the struct `r` (which took the fresh string `k` over) both release "field". Either alone is a
// double free at scope exit.
// ASan: attempting double-free, in free <- nurl_vec_drop.
// map: CallT.sink | A1 | runs-clean | h170 | string_adopt of a String's view while owner holds it: double free
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ main → i {
    : String b ( string_from `hello` )
    : String a ( string_adopt ( string_data b ) )
    : s k ( nurl_str_cat `fi` `eld` )
    : Rec r @ Rec { k 1 }
    : String c ( string_adopt . r name )
    ( nurl_println_int + ( string_len a ) ( string_len c ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
