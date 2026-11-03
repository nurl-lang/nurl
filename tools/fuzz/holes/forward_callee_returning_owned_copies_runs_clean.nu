// forward_callee_returning_owned_copies_runs_clean: a callee defined below hands back owned copies.
// The shape the fix must keep.
// main 4d57d596: runs clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a callee defined below hands back owned copies
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec String ) hold ( vec_new [String] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( mk s )
    }
    ( nurl_println ( string_data ( vec_at [String] hold 0 ) ) )
    ^ 0
}
@ mk String s → ( Vec String ) {
    : ( Vec String ) h ( vec_new [String] )
    ( vec_push [String] h ( string_from ( string_data s ) ) )
    ^ h
}
