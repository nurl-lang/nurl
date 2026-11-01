// copy_of_a_view_holding_join_returned_while_the_caller_clears_its_source: agora #335 (formal's #1610 regression 1) — a `?` join of two parameters' `( Vec s )` elements bound and returned. A copy of a view-holding type copies the views as they are, so it still reads the caller's Strings; with no return lend kept, clearing those and reading the copy was a heap-use-after-free on #1494's first head.
// Closed: the return copies a binding wherever it owns nothing only for a type that holds no views (__ret_copies_unowned asks __ty_holds_view).
// main: refused ('s' borrows from 'ps', which ended … passed to 'vec_clear').
// map: §7.6 | A2 | rejected | - | agora #335: a returned join's copy of a view-holding type keeps its lend
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick ( Vec ( Vec s ) ) ps ( Vec ( Vec s ) ) qs2 i k → ( Vec s ) {
    : ( Vec s ) r ? == k 1 ( vec_at [( Vec s )] qs2 0 ) ( vec_at [( Vec s )] ps 0 )
    ^ r
}

@ main → i {
    : ( Vec String ) owner ( vec_new [String] )
    ( vec_push [String] owner ( string_from `an owned element long enough for the heap` ) )
    : ( Vec s ) in1 ( vec_new [s] )
    ( vec_push [s] in1 ( string_data ( vec_at [String] owner 0 ) ) )
    : ( Vec ( Vec s ) ) ps ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] ps in1 )
    : ( Vec s ) in2 ( vec_new [s] )
    ( vec_push [s] in2 ( string_data ( vec_at [String] owner 0 ) ) )
    : ( Vec ( Vec s ) ) qs2 ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] qs2 in2 )
    : ( Vec s ) s ( pick ps qs2 0 )
    ( vec_clear [String] owner )
    ( nurl_println ( vec_at [s] s 0 ) )
    ^ 0
}
