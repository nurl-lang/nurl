// inout_holder_left_viewing_a_local_by_a_helper_that_does_not_repoint: the twin
// of inout_holder_pointed_back_by_a_helper_before_return_runs_clean whose
// helper returns without giving the holder a new value: still refused
// (agora #386).
// map: §3.3d | A2 | rejected | - | an inout holder given a view of a local and handed to a helper that does not repoint it before the return: refused (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ keep inout W w → i { ^ 0 }

@ fill inout W w → i {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    ^ ( keep w )
}

@ main → i {
    : ~ W w @ W { `start` }
    : i r ( fill w )
    ( nurl_println . w v )
    ^ r
}
