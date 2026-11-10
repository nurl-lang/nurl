// inout_holder_repointed_to_a_join_that_reads_a_parameter: the new value
// `@ W { ? F `y` x }` names no binding the walk saw as read at the
// assignment, but its join may be a view of the other parameter. Only a
// struct literal of literals is credited: still refused (agora #386).
// map: §3.3d | A2 | rejected | - | an inout holder repointed by a helper to a struct literal whose field is a join reading a parameter: not taken as repointed (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w s x → i { = w @ W { ? F `y` x } ^ 0 }

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
