// fixture: module; helper for private_type_argument.nu: a
// strict-mode module (it has `pub`) whose state struct stays private.
$ `stdlib/core/rcbox.nu`

: Impl { i x }

pub : H { s ctl }

unsafe pub @ H_share H h → H { ^ @ H { # s ( rcbox_share # i . h ctl ) } }

pub @ H_drop sink H h → v {
    ( mem_forget h )
    ( rcbox_release [Impl] # i . h ctl )
}

unsafe pub @ h_new → H {
    ^ @ H { # s ( rcbox_new [Impl] @ Impl { 42 } ) }
}

unsafe pub @ h_x H h → i {
    : *Impl p ( rcbox_ptr [Impl] # i . h ctl )
    ^ . p x
}
