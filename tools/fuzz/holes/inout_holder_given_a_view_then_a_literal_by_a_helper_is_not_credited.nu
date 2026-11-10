// inout_holder_given_a_view_then_a_literal_by_a_helper_is_not_credited: the
// helper's last write to its inout holder is a literal of literals, but an
// earlier statement gave it a view. Only a write that is the body's FIRST
// statement is credited: anything before it — here a write, elsewhere a
// `/` or `%` — might panic or leave a view on some path (formal's review of
// #1709). Still refused, as on main (agora #386).
// map: §3.3d | A2 | rejected | - | an inout holder a helper first gives a view, then a literal: the repoint credit needs the write to be the body's first statement (agora #386).
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
