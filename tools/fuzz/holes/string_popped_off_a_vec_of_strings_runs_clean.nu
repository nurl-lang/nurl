// string_popped_off_a_vec_of_strings_runs_clean: vec_pop of a ( Vec String ) holds no views.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 4f15689: accepted; ran clean.
// map: §2.13 | A2 | runs-clean | - | agora #368: vec_pop of a ( Vec String ) holds no views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ? String keep @ ?String { F ( string_from `` ) }
    {
        : ( Vec String ) v ( vec_new [String] )
        ( vec_push [String] v ( string_from `owned` ) )
        = keep ( vec_pop [String] v )
    }
    ?? keep { T x → ( nurl_println ( string_data x ) ) F → {} }
    ^ 0
}
