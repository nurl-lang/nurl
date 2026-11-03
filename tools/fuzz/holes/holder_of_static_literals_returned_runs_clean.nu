// holder_of_static_literals_returned_runs_clean: a returned holder of static literals outlives the String argument.
// The shape the fix must keep: static literals tie nothing.
// main 4d57d596: runs clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a returned holder of static literals outlives the String argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mkh String s → ( Vec s ) {
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h `static` )
    ^ h
}

@ main → i {
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `the first heap string, long enough to be on the heap for sure` )
        = hold ( mkh s )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
