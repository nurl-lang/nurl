// bound_literal_lends_in_param.nu — a literal of `in` parameters bound to a
// name only to be handed back (`: K k @ K { p }  ^ k`) lends them, as
// `^ @ K { p }` does: no copy of `p` is made, and the caller's argument is
// the value the result reads (D4c, AGORA-1008). The bound spelling used to
// copy `p` into `k` and hand back the copy.
$ `stdlib/core/string.nu`

: K { String s i n }

@ wrap String p i n → K {
    : K k @ K { p n }
    ^ k
}

@ main → i {
    : String a ( string_from `a string that lives on the heap` )
    : K r ( wrap a 4 )
    ( nurl_println ( string_data . r s ) )
    ( nurl_println_int . r n )
    ( nurl_println ( string_data a ) )
    ^ 0
}
