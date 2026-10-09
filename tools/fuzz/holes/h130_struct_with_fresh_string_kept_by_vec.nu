// H130: the H129 struct pushed into a Vec: the Vec keeps the struct, and nothing releases its raw string field.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ fill → i {
    : ( Vec Rec ) v ( vec_new [Rec] )
    ( vec_push [Rec] v @ Rec { ( nurl_str_cat `a` `bc` ) 1 } )
    ^ ( vec_len [Rec] v )
}

@ main → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 3 { = t + t ( fill ) = k + k 1 }
    ( nurl_print_int t ) ( nurl_print `\n` )
    ^ 0
}
