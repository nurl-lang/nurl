// H107: a method that hands back or takes a raw pointer was callable from safe code — its bare name carried no raw-memory marker, so `( addr l )` forged an address and `( byte_at l p )` read through it.
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

@ main → i {
    : Lens l @ Lens { 0 }
    : *u p ( addr l )
    ( nurl_println_int ( byte_at l p ) )
    ^ 0
}
