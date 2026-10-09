// H128: a fresh string handed straight to `vec_push [s]`: the Vec keeps the pointer but owns none of its raw strings, so nothing ever released it.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ fill → i {
    : ( Vec s ) v ( vec_new [s] )
    ( vec_push [s] v ( nurl_str_cat `a` `bc` ) )
    ^ ( vec_len [s] v )
}

@ main → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 3 { = t + t ( fill ) = k + k 1 }
    ( nurl_print_int t ) ( nurl_print `\n` )
    ^ 0
}
