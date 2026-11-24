// inout_closure_param_given_a_local_closure_holding_a_local_by_reference: as inout_closure_param_given_a_closure_holding_a_local_by_reference, through a local binding of the closure first (`= c g`).
// Closed: the binding carries the closure's stack reference (`__refdepth`), and assigning it into the `inout` parameter is refused (AGORA-1001).
// main's compiler: compiled with no `unsafe`; ASan reports stack-use-after-scope.
// map: §2.3 | A2 | rejected | h986 | a local closure binding capturing a callee local by reference assigned to an inout closure parameter (AGORA-1001)
@ set inout ( @ i ) c → i {
    : ~ i w 5
    : ( @ i ) g \ → i { = w + w 1 ^ w }
    = c g
    ^ 0
}

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 1 }
    ( set f )
    ^ ( f )
}
