// fixture: module; helper for private_handle_payload.nu: a strict-mode
// module (it has `pub`) whose public handle shares a private struct, and
// leaves the handle's drop to the compiler.
$ `stdlib/core/rcbox.nu`
$ `stdlib/core/string.nu`

: Impl { String name i n }

pub : H { ( Shared Impl ) ctl }

unsafe pub @ H_share H h → H { ^ @ H { ( shared_clone [Impl] . h ctl ) } }

unsafe pub @ h_new s name i n → H {
    ^ @ H { ( shared_new [Impl] @ Impl { ( string_from name ) n } ) }
}

unsafe pub @ h_n H h → i {
    : *Impl p ( shared_ptr [Impl] . h ctl )
    ^ . p n
}
