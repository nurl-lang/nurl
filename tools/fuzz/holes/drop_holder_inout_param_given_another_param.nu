// drop_holder_inout_param_given_another_param: agora #284 — an `inout` `% Drop` holder given a view of another parameter (the caller's too, older than the holder's destructor runs): accepted (the shape the fix must keep).
// Closed: an `inout` parameter whose drop may read the views it holds is a holder older than every local of the callee: given a view of one, even for a moment, it is refused where it gains the view (bck_younger_view_check, the `^` parameter mark; agora #284).
// main: accepted; ran clean.
// map: §2.14 | A2 | runs-clean | - | agora #284: an inout Drop holder given a view of another parameter
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ repoint inout W w String src → v {
    = w @ W { ( string_data src ) }
}

@ main → i {
    : String s ( string_from `the caller's string, older than w` )
    : ~ W w @ W { `literal` }
    ( repoint w s )
    ^ 0
}
