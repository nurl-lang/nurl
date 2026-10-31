// drop_holder_inout_param_given_a_callee_local_then_panics: agora #284 — an `inout` callee points the caller's `% Drop` view holder at its own local, puts it back before returning, and panics in between: the unwind frees the local, then the holder's destructor reads it.
// Closed: an `inout` parameter whose drop may read the views it holds is a holder older than every local of the callee: given a view of one, even for a moment, it is refused where it gains the view (bck_younger_view_check, the `^` parameter mark; agora #284).
// main: accepted; AddressSanitizer reported heap-use-after-free (nurl__jrnl_drain).
// map: §2.14 | A2 | rejected | - | agora #284: an inout Drop holder given a callee local's view, then a panic
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ repoint inout W w i k → v {
    : String b ( string_from `the callee's own string, freed by the unwind before the holder's destructor reads it` )
    = w @ W { ( string_data b ) }
    ? > k 2 { ( panic `unwind` ) } {}
    = w @ W { `literal again` }
}

@ f i k → v {
    : ~ W w @ W { `literal` }
    ( repoint w k )
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( f 3 ) } )
    ( puts `ran` )
    ^ 0
}
