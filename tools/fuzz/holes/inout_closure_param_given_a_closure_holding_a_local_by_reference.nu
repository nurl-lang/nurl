// inout_closure_param_given_a_closure_holding_a_local_by_reference: a callee assigns its `inout` closure parameter a closure that assigns, so captures by reference, the callee's scalar local `w`. The caller runs it after the callee returned, through `w`'s dead stack slot.
// Closed: an `inout` parameter is the caller's storage, which outlives every binding of the frame, so a stack reference assigned into it is refused (bck_esc_assign, AGORA-1001).
// main's compiler: compiled with no `unsafe`; ASan reports stack-use-after-scope, a READ of the callee's local.
// map: §2.3 | A2 | rejected | h984 | a closure capturing a callee local by reference assigned to an inout closure parameter, then run by the caller (AGORA-1001)
@ set inout ( @ i ) c → i {
    : ~ i w 5
    = c \ → i { = w + w 1 ^ w }
    ^ 0
}

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 1 }
    ( set f )
    ^ ( f )
}
