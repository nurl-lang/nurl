// in_param_lent_back_by_a_bound_literal_read_after_runs_clean: a literal of an `in` parameter bound only to be handed back (`: K k @ K { p }  ^ k`) lends it, as `^ @ K { p }` does: the caller keeps its argument and reads it after it has used the result.
// D4c's bound spelling (AGORA-1008): before it a hidden copy of `p` was made into `k`.
// map: §7.6 | A2 | runs-clean | - | AGORA-1008: an `in` parameter handed back in a bound literal is lent
$ `stdlib/core/string.nu`

: K { String s i n }

@ wrap String p → K {
    : K k @ K { p 1 }
    ^ k
}

@ main → i {
    : String a ( string_from `a string that lives on the heap` )
    : K r ( wrap a )
    ( nurl_println ( string_data . r s ) )
    ( nurl_println ( string_data a ) )
    ^ 0
}
