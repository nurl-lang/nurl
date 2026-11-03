// vec_param_kept_in_a_returned_struct: a ( Vec s ) parameter stored into a struct handed back.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #362: a ( Vec s ) parameter stored into a struct handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec s ) a }

@ hold ( Vec s ) v → H { ^ @ H { v } }

@ main → i {
    : ~ H ws @ H { ( vec_new [s] ) }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = ws ( hold t )
    }
    ( nurl_println ( vec_at [s] . ws a 0 ) )
    ^ 0
}
