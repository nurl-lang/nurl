// inout_holder_repointed_only_after_a_call: a helper that repoints its inout holder, but only
// in a way the #386 summary must not credit (see the name): the caller is
// still refused for leaving its holder viewing a local (agora #386).
// map: §3.3d | A2 | rejected | - | an inout holder handed to a helper repointed only after a call: not taken as repointed on every path (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w → i { ( nurl_println `about to repoint` ) = w @ W { `lit` } ^ 0 }

@ fill inout W w → i {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    ^ ( reset w )
}

@ main → i { : ~ W w @ W { `start` } : i r ( fill w ) ( nurl_println . w v ) ^ r }
