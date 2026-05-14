// Test: stdlib/core/vec.nu — vec_contains / vec_index_of / vec_eq
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`
$ `stdlib/std/hashmap.nu`

@ main → i {
    : ( @ b i i ) ei \ i a i b → b { ^ == a b }
    : ( @ b s s ) es \ s a s b → b { ^ ( eq_string a b ) }

    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 10 )
    ( vec_push [i] v 20 )
    ( vec_push [i] v 30 )
    ( vec_push [i] v 20 )

    ( nurl_print `contains_20=` )
    ( nurl_print ? ( vec_contains [i] v 20 ei ) `T` `F` )
    ( nurl_print `\n` )

    ( nurl_print `contains_99=` )
    ( nurl_print ? ( vec_contains [i] v 99 ei ) `T` `F` )
    ( nurl_print `\n` )

    // index_of returns first match
    : ?i idx20 ( vec_index_of [i] v 20 ei )
    ( nurl_print `index_20=` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] idx20 -1 ) ) )
    ( nurl_print `\n` )

    : ?i idx99 ( vec_index_of [i] v 99 ei )
    ( nurl_print `index_99_none=` )
    ?? idx99 {
        T x → ( nurl_print `NO\n` )
        F → ( nurl_print `YES\n` )
    }

    // vec_eq same-length
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    ( vec_push [i] a 2 )
    ( vec_push [i] a 3 )

    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    ( vec_push [i] b 3 )

    ( nurl_print `eq_same=` )
    ( nurl_print ? ( vec_eq [i] a b ei ) `T` `F` )
    ( nurl_print `\n` )

    // mutate one element → no longer equal
    ( vec_set [i] b 1 99 )
    ( nurl_print `eq_diff=` )
    ( nurl_print ? ( vec_eq [i] a b ei ) `T` `F` )
    ( nurl_print `\n` )

    // different lengths
    ( vec_push [i] b 4 )
    ( nurl_print `eq_lendiff=` )
    ( nurl_print ? ( vec_eq [i] a b ei ) `T` `F` )
    ( nurl_print `\n` )

    // both empty → equal
    : ( Vec i ) e1 ( vec_new [i] )
    : ( Vec i ) e2 ( vec_new [i] )
    ( nurl_print `eq_empty=` )
    ( nurl_print ? ( vec_eq [i] e1 e2 ei ) `T` `F` )
    ( nurl_print `\n` )

    // string-vec contains using eq_string (raw s)
    : ( Vec s ) words ( vec_new [s] )
    ( vec_push [s] words `apple` )
    ( vec_push [s] words `banana` )
    ( vec_push [s] words `cherry` )

    ( nurl_print `str_contains_banana=` )
    ( nurl_print ? ( vec_contains [s] words `banana` es ) `T` `F` )
    ( nurl_print `\n` )

    : ?i sidx ( vec_index_of [s] words `cherry` es )
    ( nurl_print `str_index_cherry=` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] sidx -1 ) ) )
    ( nurl_print `\n` )

    ( vec_free [s] words )
    ( vec_free [i] e2 )
    ( vec_free [i] e1 )
    ( vec_free [i] b )
    ( vec_free [i] a )
    ( vec_free [i] v )
    ( nurl_print `done\n` )
    ^ 0
}
