// diag_cc_handle_without_trace.nu — a library handle type (one with its
// own `_drop`) whose payload can hold an Rc is opaque to the cycle
// collector unless its module defines a `_trace` function that hands the
// collector what it holds (docs/MEMORY.md §7.7). Without one, a cycle
// through the handle would never be found, so the program is rejected
// and the message names the type and the function to add.
$ `stdlib/core/mem.nu`
$ `stdlib/std/rc.nu`

: Slot [A] { s ptr }

unsafe @ slot_new [A] A x → ( Slot A ) {
    : *A p ( alloc [A] 1 )
    = . p 0 x
    ^ @ ( Slot A ) { # s p }
}

unsafe @ Slot_drop [A] sink ( Slot A ) h → v {
    ( mem_forget h )
    : *A p # *A . h ptr
    ? != 0 # i p {
        : A v . p 0
        ( mem_take v )
        ( nurl_free # s p )
    } {}
}

unsafe @ Slot_clone [A] ( Slot A ) h → ( Slot A ) {
    : *A src # *A . h ptr
    ? == 0 # i src { ^ @ ( Slot A ) { # s 0 } } {}
    : *A p ( alloc [A] 1 )
    : A v . src 0
    = . p 0 ( mem_dup v )
    ^ @ ( Slot A ) { # s p }
}

: Node { i id ( Slot ( Rc Node ) ) next }

unsafe @ main → i {
    : ( Rc Node ) a ( rc_new [Node] @ Node { 1 ( slot_new [( Rc Node )] ( rc_zero [Node] ) ) } )
    ^ - . ( rc_get [Node] a ) id 1
}
