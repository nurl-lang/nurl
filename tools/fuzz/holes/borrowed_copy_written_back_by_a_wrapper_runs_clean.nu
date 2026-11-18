// borrowed_copy_written_back_by_a_wrapper_runs_clean: take_body hands the copy to `checkin`, a safe wrapper that always writes it back
// AGORA-870 guard: accepted - the wrapper writes back on every run
// map: §7.6 | A2 | runs-clean | - | AGORA-870
$ `stdlib/core/vec.nu`

: Slot { i id ( Vec u ) body }

// (unsafe: vec_put_back is the raw write-back protocol; the rest is safe code)
unsafe @ put_slot ( Vec Slot ) t i k Slot s → v { ( vec_put_back [Slot] t k s ) }

@ checkin ( Vec Slot ) t i k Slot s i c → v { ( put_slot t k s ) }

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
