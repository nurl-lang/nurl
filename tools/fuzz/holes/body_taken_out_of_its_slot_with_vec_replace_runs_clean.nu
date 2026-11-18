// body_taken_out_of_its_slot_with_vec_replace_runs_clean: `?? ( vec_replace [Slot] t k @ Slot { k ( vec_new [u] ) } ) { T old → { ^ . old body } … }` - the slot is given a new element, and the old one is this function's
// AGORA-870 guard: accepted - the safe spelling of taking a body out of a slot
// map: §7.6 | A2 | runs-clean | - | AGORA-870
$ `stdlib/core/vec.nu`

: Slot { i id ( Vec u ) body }

@ take_body ( Vec Slot ) t i k i c → ( Vec u ) {
    ?? ( vec_replace [Slot] t k @ Slot { k ( vec_new [u] ) } ) {
        T old → { ^ . old body }
        F → { ^ ( vec_new [u] ) }
    }
}

@ main → i {
    : ( Vec Slot ) t ( vec_new [Slot] )
    : ( Vec u ) b ( vec_new [u] ) ( vec_push [u] b # u 7 ) ( vec_push [u] b # u 8 )
    ( vec_push [Slot] t @ Slot { 1 b } )
    : ( Vec u ) got ( take_body t 0 1 )
    ( vec_push [u] got # u 9 )
    ^ ( vec_len [u] got )
}
