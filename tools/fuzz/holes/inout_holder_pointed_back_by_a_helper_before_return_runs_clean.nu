// inout_holder_pointed_back_by_a_helper_before_return_runs_clean: a callee
// gives its `inout` holder a view of its own local, then hands it to a helper
// that gives the holder a whole new value (`= w @ W { `literal` }`) before
// any call or exit, and returns. The walk did not know the helper replaces its
// parameter, so it refused the callee as leaving the caller's holder viewing
// the local. Closed (agora #386): a function that repoints an `inout`
// parameter at its top level before any call or exit says so (`repoints##`),
// and its caller's walk takes the argument as given a new value.
// map: §3.3d | A2 | runs-clean | - | an inout holder given a view of a local, then repointed whole by a helper before the return: refused as still viewing the local (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w → i { = w @ W { `literal` } ^ 0 }

@ fill inout W w → i {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    ( nurl_println . w v )
    ^ ( reset w )
}

@ main → i {
    : ~ W w @ W { `start` }
    : i r ( fill w )
    ( nurl_println . w v )
    ^ r
}
