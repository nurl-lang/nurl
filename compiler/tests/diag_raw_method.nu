// diag_raw_method.nu — a method that hands back or takes a raw pointer is
// raw memory to call, whichever impl the call reaches, as a plain function
// of that signature is (diag_raw_boundary.nu): `( addr l )` forged an
// address from safe code, and `( byte_at l p )` read through it. Checked
// for a call the receiver's type dispatches statically and for one through
// a trait object alike (h107).
$ `stdlib/core/string.nu`

% Peek [T] {
    @ addr T self → *u
    @ byte_at T self * u p → i
}

: Lens { i k }

% Peek Lens {
    unsafe @ addr Lens l → *u { ^ # *u 4096 }
    unsafe @ byte_at Lens l * u p → i { ^ # i . p 0 }
}

@ static_call → i {
    : Lens l @ Lens { 0 }
    : *u p ( addr l )
    ^ 0
}

@ dyn_call → i {
    : Lens l @ Lens { 0 }
    : %Peek d ( dyn Peek l )
    : *u p ( addr d )
    ^ 0
}

@ main → i {
    ^ 0
}
