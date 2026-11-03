// fresh_result_beside_a_string_param_runs_clean: a fresh result outlives the String argument.
// The shape the fix must keep: a fresh result ties nothing.
// main 4d57d596: runs clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a fresh result outlives the String argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk String s → ( Vec String ) {
    : ( Vec String ) h ( vec_new [String] )
    ( vec_push [String] h ( string_from `fresh` ) )
    ^ h
}

@ main → i {
    : ~ ( Vec String ) hold ( vec_new [String] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( mk s )
    }
    ( nurl_println ( string_data ( vec_at [String] hold 0 ) ) )
    ^ 0
}
