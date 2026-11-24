// lent_literal_result_read_after_its_argument_is_reassigned: the result of `^ @ K { p 0 }` read after the caller gave its argument a new value - the old String was released
// D4c (AGORA-995): an `in` parameter handed back in a literal is lent, so the result borrows the caller's argument; using it after the argument is gone is refused, as for `^ p`.
// map: §2.5 | A2 | rejected | - | AGORA-995: the result of `^ @ K { p 0 }` read after the caller gave its argument a new value
$ `stdlib/core/string.nu`
: K { String a i n }

@ wrap String p → K {
    ^ @ K { p 0 }
}

@ main → i {
    : ~ String s ( string_from `a string long enough for the heap buffer here` )
    : K k ( wrap s )
    = s ( string_from `another string long enough for the heap buffer` )
    ( nurl_println ( string_data . k a ) )
    ^ 0
}
