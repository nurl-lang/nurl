// fold_pushing_views_into_its_accumulator: vec_fold pushing the views of a Vec into its accumulator, kept past the strings.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #377: vec_fold pushing the views of a Vec into its accumulator, kept past the strings
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = ws ( vec_fold [s ( Vec s )] t ( vec_new [s] ) \ ( Vec s ) acc s x → ( Vec s ) { ( vec_push [s] acc x ) ^ acc } )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
