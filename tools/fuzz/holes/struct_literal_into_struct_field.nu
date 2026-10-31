// struct_literal_into_struct_field: a struct literal with a fresh raw string field stored into a field of another struct: neither the store nor the outer binding released it.
// map: §2.13 | A2 | rejected | h137 | struct literal with fresh s field stored into outer field leaks
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

: Outer { Rec r i k }

@ fill → i {
    : ~ Outer o @ Outer { @ Rec { `a` 1 } 2 }
    = . o r @ Rec { ( nurl_str_cat `c` `de` ) 3 }
    ^ ( nurl_str_len . . o r name )
}

@ main → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 3 { = t + t ( fill ) = k + k 1 }
    ( nurl_print_int t ) ( nurl_print `\n` )
    ^ 0
}
