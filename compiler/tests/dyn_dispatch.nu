// dyn_dispatch.nu
// Dynamic trait objects (docs/spec.md §4.9): a `%Trait` value is a fat pointer
// { data, vtable }. A function taking `%Speaker` dispatches `speak` indirectly
// through the vtable, so ONE `announce` works over any concrete implementor —
// the two calls below reach Dog.speak and Robot.speak with no static type known
// at the call site. Also exercises a non-Self value parameter (`i volume`).

% Speaker [T] {
    @ speak T self i volume → i
}

: Dog { i pitch }
: Robot { i serial }

% Speaker Dog   { @ speak Dog d   i volume → i { : i p . d pitch    ^ + p volume } }
% Speaker Robot { @ speak Robot r i volume → i { : i sn . r serial  ^ * sn volume } }

// Static-dispatch-free: `s` is only known to be *some* Speaker.
@ announce %Speaker s i volume → i { ^ ( speak s volume ) }

@ main → i {
    : Dog d @ Dog { 10 }
    : Robot r @ Robot { 3 }
    : %Speaker sd ( dyn Speaker d )
    : %Speaker sr ( dyn Speaker r )
    : i a ( announce sd 5 )   // Dog.speak: 10 + 5 = 15
    : i b ( announce sr 4 )   // Robot.speak: 3 * 4 = 12
    ( nurl_print_int a )
    ( nurl_print_int b )
    ( nurl_print_int + a b )  // 27
    ^ 0
}
