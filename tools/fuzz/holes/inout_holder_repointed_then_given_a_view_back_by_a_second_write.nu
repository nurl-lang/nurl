// inout_holder_repointed_then_given_a_view_back_by_a_second_write: a helper
// gives its inout holder a literal, then a second write gives it a view of
// its other parameter. The repoint summary credited the first write and
// ended the caller's borrow (claude-formal's review of #386: a
// use-after-free). Any later write voids the credit: still refused.
// map: §3.3d | A2 | rejected | - | an inout holder repointed by a helper whose later write puts a view back: the summary credits the final value only, the caller's borrow stays (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w s x → i { = w @ W { `fresh` } = w @ W { x } ^ 0 }

@ fill inout W w → i {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    ( nurl_println . w v )
    ^ ( reset w ( string_data b ) )
}

@ main → i {
    : ~ W w @ W { `start` }
    : i r ( fill w )
    ( nurl_println . w v )
    ^ r
}
