// inout_holder_repointed_then_a_field_store_puts_a_view_back: the helper
// repoints its inout holder whole, then `= . w v x` stores a view of its
// other parameter into a field. A field store after the credited write
// voids it: still refused (agora #386).
// map: §3.3d | A2 | rejected | - | an inout holder repointed by a helper whose later field store puts a view back: not taken as repointed (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w s x → i { = w @ W { `fresh` } = . w v x ^ 0 }

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
