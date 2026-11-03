// holder_of_owned_copies_returned_runs_clean: a returned holder of owned copies outlives the String.
// The shape the fix must keep: owned copies tie nothing.
// main 4d57d596: runs clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a returned holder of owned copies outlives the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mkh String s → ( Vec String ) {
    : ( Vec String ) h ( vec_new [String] )
    ( vec_push [String] h ( string_from ( string_data s ) ) )
    ^ h
}

@ main → i {
    : ~ ( Vec String ) hold ( vec_new [String] )
    {
        : String s ( string_from `the first heap string, long enough to be on the heap for sure` )
        = hold ( mkh s )
    }
    ( nurl_println ( string_data ( vec_at [String] hold 0 ) ) )
    ^ 0
}
