// H138: a join of two struct literals, one with a fresh raw string field, bound: the binding registered the other arm's fields, and the fresh one leaked.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ f b c → i {
    : Rec r ? c @ Rec { ( nurl_str_cat `a` `bc` ) 1 } @ Rec { `x` 2 }
    ^ ( nurl_str_len . r name )
}

@ main → i {
    ( nurl_print_int + ( f T ) ( f F ) ) ( nurl_print `\n` )
    ^ 0
}
