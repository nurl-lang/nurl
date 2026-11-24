// lent_literal_result_read_after_its_argument_is_sunk: the result of `^ @ K { p 0 }` read after the caller handed its argument to a `sink` - the String it holds was released
// D4c (AGORA-995): an `in` parameter handed back in a literal is lent, so the result borrows the caller's argument; using it after the argument is gone is refused, as for `^ p`.
// map: §2.5 | A2 | rejected | - | AGORA-995: the result of `^ @ K { p 0 }` read after the caller handed its argument to a `sink`
$ `stdlib/core/string.nu`

: K { String a i n }

@ wrap String p → K {
    ^ @ K { p 0 }
}

@ eat sink String x → i { ^ 0 }

@ main → i {
    : String s ( string_from `a string long enough for the heap buffer here` )
    : K k ( wrap s )
    ( eat s )
    ( nurl_println ( string_data . k a ) )
    ^ 0
}
