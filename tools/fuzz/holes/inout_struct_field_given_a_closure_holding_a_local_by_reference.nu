// inout_struct_field_given_a_closure_holding_a_local_by_reference: a callee stores into a field of its `inout` struct parameter a closure that captures its scalar local by reference. The caller runs the field's closure after the callee returned.
// Closed: a field of an `inout` parameter is the caller's storage, and a stack reference stored into it is refused (bck_esc_field_store, AGORA-1001).
// main's compiler: compiled with no `unsafe`; ASan reports stack-use-after-scope.
// map: §2.3 | A2 | rejected | h985 | a closure capturing a callee local by reference stored into a field of an inout struct parameter (AGORA-1001)
: R { ( @ i ) c i n }

@ set inout R r → i {
    : ~ i w 5
    = . r c \ → i { = w + w 1 ^ w }
    ^ 0
}

@ main → i {
    : ~ R x @ R { \ → i { ^ 1 } 0 }
    ( set x )
    : ( @ i ) g . x c
    ^ ( g )
}
