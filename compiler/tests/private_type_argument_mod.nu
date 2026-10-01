// fixture: module; helper for private_type_argument.nu: a
// strict-mode module (it has `pub`) whose state struct stays private.
$ `stdlib/core/rcbox.nu`

: Impl { i x }

pub : H { s ctl }

pub @ h_new → H {
    ^ @ H { # s ( rcbox_new [Impl] @ Impl { 42 } ) }
}

pub @ h_x H h → i {
    : *Impl p ( rcbox_ptr [Impl] # i . h ctl )
    ^ . p x
}
