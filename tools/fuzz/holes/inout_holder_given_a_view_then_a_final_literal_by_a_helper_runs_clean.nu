// inout_holder_given_a_view_then_a_final_literal_by_a_helper_runs_clean: the
// helper's last write to its inout holder is a literal of literals, before
// any call, defer or exit; an earlier write gave it a view. The credit is
// the parameter's final value (agora #386), so the caller's holder no longer
// views its local.
// map: §3.3d | A2 | runs-clean | - | an inout holder that a helper first gives a view, then a literal as its last write: taken as repointed, the caller's borrow of the local ends (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w s x → i { = w @ W { x } = w @ W { `fresh` } ^ 0 }

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
