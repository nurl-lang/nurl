// inout_holder_repointed_with_a_defer_armed_before: the helper arms a defer
// that gives its inout holder a view, then repoints it to a literal. The
// defer runs after the repoint, so the holder ends viewing. A function with
// a defer gets no repoint summary: still refused (agora #386).
// map: §3.3d | A2 | rejected | - | an inout holder repointed by a helper that armed a defer before: the defer may put a view back, so not taken as repointed (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w s x → i { ; { = w @ W { x } } = w @ W { `fresh` } ^ 0 }

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
