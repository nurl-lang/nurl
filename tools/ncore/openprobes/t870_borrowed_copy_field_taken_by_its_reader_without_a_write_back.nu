// borrowed_copy_field_taken_by_its_reader_without_a_write_back.nu — a
// struct read out of a table by value is a copy the table still owns. A
// field of it read into a binding, the field then replaced in the copy:
// the store hands the old value to that binding, which owns it from there
// on. Without the copy written back into its slot, the slot still holds
// the very same body: the caller's result and the caller's table both
// release it (lend_back_to_same_binding.nu's take_body with its put_slot
// removed).
//
// map: §7.6 | A2 | rejected | - | agora #870: a field of a borrowed copy handed to its reader by the store that replaces it, the copy never written back: the slot and the result own one body

$ `stdlib/core/vec.nu`

: Slot { i id ( Vec u ) body }

unsafe @ get_slot ( Vec Slot ) t i k → Slot {
    : *Slot sp ( vec_data [Slot] t )
    ^ . sp k
}

@ take_body ( Vec Slot ) t i k → ( Vec u ) {
    : Slot s ( get_slot t k )
    : ( Vec u ) out . s body
    = . s body ( vec_new [u] )
    ^ out
}

@ main → i {
    : ( Vec Slot ) t ( vec_new [Slot] )
    : ( Vec u ) b ( vec_new [u] ) ( vec_push [u] b # u 7 ) ( vec_push [u] b # u 8 )
    ( vec_push [Slot] t @ Slot { 1 b } )
    : ( Vec u ) got ( take_body t 0 )
    ( vec_push [u] got # u 9 )
    ^ ( vec_len [u] got )
}
