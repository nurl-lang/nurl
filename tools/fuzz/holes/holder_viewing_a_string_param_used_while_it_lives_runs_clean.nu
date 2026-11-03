// holder_viewing_a_string_param_used_while_it_lives_runs_clean: a returned holder used while the String lives.
// The shape the fix must keep.
// main 4d57d596: runs clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a returned holder used while the String lives
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
@ mkh String s → ( Vec s ) {
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data s ) )
    ^ h
}
@ main → i {
    : String s ( string_from `the first heap string, long enough to be on the heap for sure` )
    : ( Vec s ) hold ( mkh s )
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
