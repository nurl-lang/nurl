// borrowed_copy_field_taken_then_an_early_return_before_the_write_back: the write-back after an early `^ out` on `? > c 0`
// AGORA-870: refused - the early return leaves with the slot still owning out's body
// map: §7.6 | A2 | rejected | - | AGORA-870
$ `stdlib/core/vec.nu`

: Slot { i id ( Vec u ) body }

// (unsafe: vec_put_back is the raw write-back protocol; take_body itself is safe code)
unsafe @ put_slot ( Vec Slot ) t i k Slot s → v { ( vec_put_back [Slot] t k s ) }

@ take_body ( Vec Slot ) t i k i c → ( Vec u ) {
    : Slot s ( vec_at [Slot] t k )
    : ( Vec u ) out . s body
    = . s body ( vec_new [u] )
    ? > c 0 { ^ out } {}
    ( put_slot t k s )
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
