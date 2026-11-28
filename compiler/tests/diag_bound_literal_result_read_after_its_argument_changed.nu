// diag_bound_literal_result_read_after_its_argument_changed.nu — the
// result of a function that hands back a bound literal of its `in`
// parameter borrows the caller's argument (D4c, AGORA-1008): read after the
// argument is given a new value, it is refused, as the direct spelling
// `^ @ K { p }` is. Before, the bound spelling copied, and this compiled.
$ `stdlib/core/string.nu`

: K { String s }

@ wrap String p → K {
    : K k @ K { p }
    ^ k
}

@ main → i {
    : ~ String a ( string_from `a string that lives on the heap` )
    : K r ( wrap a )
    = a ( string_from `other` )
    ( nurl_println ( string_data . r s ) )
    ^ 0
}
