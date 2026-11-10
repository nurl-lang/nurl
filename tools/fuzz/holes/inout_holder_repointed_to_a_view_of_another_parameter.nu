// inout_holder_repointed_to_a_view_of_another_parameter: a helper that repoints its inout holder, but only
// in a way the #386 summary must not credit (see the name): the caller is
// still refused for leaving its holder viewing a local (agora #386).
// map: §3.3d | A2 | rejected | - | an inout holder handed to a helper repointed to a view of another parameter: not taken as repointed on every path (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w W q → i { = w @ W { . q v } ^ 0 }

@ fill inout W w W q → i {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    ^ ( reset w q )
}

@ main → i {
    : String t ( string_from `caller text long enough for the heap` )
    : W q @ W { ( string_data t ) }
    : ~ W w @ W { `start` }
    : i r ( fill w q )
    ( string_free t )
    ( nurl_println . w v )
    ^ r
}
