// inout_holder_repointed_then_given_a_view_back_in_an_arm: the helper
// repoints its inout holder to a literal at its top level, then an arm
// gives it a view of its other parameter. A later write at any depth voids
// the repoint credit (formal's review of #386): still refused.
// map: §3.3d | A2 | rejected | - | an inout holder repointed by a helper whose later write in an arm puts a view back: not taken as repointed (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w s x i c → i { = w @ W { `fresh` } ? == c 1 { = w @ W { x } } {} ^ 0 }

@ fill inout W w → i {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    ( nurl_println . w v )
    ^ ( reset w ( string_data b ) 1 )
}

@ main → i {
    : ~ W w @ W { `start` }
    : i r ( fill w )
    ( nurl_println . w v )
    ^ r
}
