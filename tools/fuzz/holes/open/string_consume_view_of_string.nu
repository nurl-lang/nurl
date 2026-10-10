// OPEN in 0.72.0 — string_adopt of a view takes the buffer over while its owner still holds it: released twice.
// ( string_adopt ( string_data b ) ): `a` and `b` both release "hello"'s buffer. ( string_adopt . r name ):
// `c` and the struct `r` (which took the fresh string `k` over) both release "field". Either alone is a
// double free at scope exit.
// ASan: attempting double-free, in free <- nurl_vec_drop.
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
