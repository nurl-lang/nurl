// lent_variant_result_read_after_its_argument_is_sunk: the result of `^ @ E { V p }` matched after the caller handed its argument to a `sink`
// D4c (AGORA-995): an `in` parameter handed back in a literal is lent, so the result borrows the caller's argument; using it after the argument is gone is refused, as for `^ p`.
// map: §2.5 | A2 | rejected | - | AGORA-995: the result of `^ @ E { V p }` matched after the caller handed its argument to a `sink`
$ `stdlib/core/string.nu`

: | E { V String W i }

@ wrap String p → E {
    ^ @ E { V p }
}

@ eat sink String x → i { ^ 0 }

@ main → i {
    : String s ( string_from `a string long enough for the heap buffer here` )
    : E e ( wrap s )
    ( eat s )
    ?? e { V x → { ( nurl_println ( string_data x ) ) } W n → {} }
    ^ 0
}
