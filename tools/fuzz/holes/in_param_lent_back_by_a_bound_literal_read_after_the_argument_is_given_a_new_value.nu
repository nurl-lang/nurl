// in_param_lent_back_by_a_bound_literal_read_after_the_argument_is_given_a_new_value: the result of `: K k @ K { p }  ^ k` borrows the caller's argument; read after the argument is given a new value, it reads freed memory.
// AGORA-1008: refused - the result borrows the argument, as `^ @ K { p }`'s does (before it the bound spelling copied and this compiled, clean only because of the copy)
// map: §7.6 | A2 | rejected | - | AGORA-1008: a bound literal handed back lends the caller's argument; the result read after the argument is reassigned
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
