// function_handing_back_literals_runs_clean: a function given a ( Vec s ) hands back a Vec of literals.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 836c0e9: accepted; ran clean.
// map: §2.8 | A2 | runs-clean | - | agora #377: a function given a ( Vec s ) hands back a Vec of literals
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ kinds ( Vec s ) v → ( Vec s ) { : ( Vec s ) o ( vec_new [s] ) ( vec_push [s] o `kind` ) ^ o }

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = ws ( kinds t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
