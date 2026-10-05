// rc_move_only_handle_field.nu — a struct holding a handle that cannot be
// copied (a `_drop` and no `_clone`) stored by a callee into memory it
// returns: `rc_new` keeps its argument whatever the argument's type. The
// keep was settled only for a parameter the callee itself drops, so for a
// value that cannot be copied the caller dropped the literal's handle after
// the call while the Rc held it — a use-after-free on main (reading the
// node's slot back).
$ `stdlib/std/rc.nu`

: SlotImpl [A] { A value }

: Slot [A] { s ctl }

@ slot_new [A] A x → ( Slot A ) {
    : *( SlotImpl A ) impl # *( SlotImpl A ) ( nurl_alloc Z ( SlotImpl A ) )
    = . impl value x
    ^ @ ( Slot A ) { # s impl }
}

@ Slot_drop [A] sink ( Slot A ) h → v {
    ( mem_forget h )
    ? == 0 # i . h ctl { ^ } {}
    : *( SlotImpl A ) impl # *( SlotImpl A ) . h ctl
    : A v . impl value
    ( mem_take v )
    ( nurl_free # s impl )
}

@ Slot_trace [A] ( Slot A ) h s vis → v {
    ? == 0 # i . h ctl { ^ } {}
    : *( SlotImpl A ) impl # *( SlotImpl A ) . h ctl
    ( mem_trace [A] . impl value vis )
}

: Node { i id ( Slot ( Rc Node ) ) next }

@ main → i {
    : ( Rc Node ) a ( rc_new [Node] @ Node { 1 ( slot_new [( Rc Node )] ( rc_zero [Node] ) ) } )
    : *( SlotImpl ( Rc Node ) ) si # *( SlotImpl ( Rc Node ) ) . . ( rc_get [Node] a ) next ctl
    : ( Rc Node ) inner . si value
    ( nurl_print_int ( rc_strong [Node] inner ) ) ( nurl_print `\n` )
    ^ - . ( rc_get [Node] a ) id 1
}
