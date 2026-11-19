// borrowed_copy_field_taken_through_a_safe_getter_without_a_write_back: `: Slot s ( vec_at [Slot] t k )  : ( Vec u ) out . s body  = . s body ( vec_new )  ^ out`
// AGORA-870: refused - the slot and out own one body (main: accepted, heap-use-after-free)
// map: §7.6 | A2 | rejected | - | AGORA-870
$ `stdlib/core/vec.nu`

: Slot { i id ( Vec u ) body }

@ take_body ( Vec Slot ) t i k i c → ( Vec u ) {
    : Slot s ( vec_at [Slot] t k )
    : ( Vec u ) out . s body
    = . s body ( vec_new [u] )
    ^ out
}

@ main → i {
    : ( Vec Slot ) t ( vec_new [Slot] )
    : ( Vec u ) b ( vec_new [u] ) ( vec_push [u] b # u 7 ) ( vec_push [u] b # u 8 )
    ( vec_push [Slot] t @ Slot { 1 b } )
    : ( Vec u ) got ( take_body t 0 1 )
    ( vec_push [u] got # u 9 )
    ^ ( vec_len [u] got )
}
