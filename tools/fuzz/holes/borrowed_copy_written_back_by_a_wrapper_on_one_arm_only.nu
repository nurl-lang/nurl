// borrowed_copy_written_back_by_a_wrapper_on_one_arm_only: take_body hands the copy to `checkin`, a safe wrapper that writes it back only when its flag says so
// AGORA-870 (CodeRabbit on github#1959): refused - the wrapper writes back on some runs only, so it settles no caller's debt
// map: §7.6 | A2 | rejected | - | AGORA-870
$ `stdlib/core/vec.nu`

: Slot { i id ( Vec u ) body }

// (unsafe: vec_put_back is the raw write-back protocol; the rest is safe code)
unsafe @ put_slot ( Vec Slot ) t i k Slot s → v { ( vec_put_back [Slot] t k s ) }

@ checkin ( Vec Slot ) t i k Slot s i c → v { ? > c 0 { ( put_slot t k s ) } {} }

@ take_body ( Vec Slot ) t i k i c → ( Vec u ) {
    : Slot s ( vec_at [Slot] t k )
    : ( Vec u ) out . s body
    = . s body ( vec_new [u] )
    ( checkin t k s c )
    ^ out
}

@ main → i {
    : ( Vec Slot ) t ( vec_new [Slot] )
    : ( Vec u ) b ( vec_new [u] ) ( vec_push [u] b # u 7 ) ( vec_push [u] b # u 8 )
    ( vec_push [Slot] t @ Slot { 1 b } )
    : ( Vec u ) got ( take_body t 0 0 )
    ( vec_push [u] got # u 9 )
    ^ ( vec_len [u] got )
}
