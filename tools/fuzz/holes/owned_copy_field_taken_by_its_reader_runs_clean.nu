// owned_copy_field_taken_by_its_reader_runs_clean: `: Slot s @ Slot { 1 ( vec_new ) }  : ( Vec u ) out . s body  = . s body ( vec_new )  ^ out` - s owns its value
// AGORA-870 guard: accepted - an owner's field taken by its reader is the reader's alone
// map: §7.6 | A2 | runs-clean | - | AGORA-870
$ `stdlib/core/vec.nu`

: Slot { i id ( Vec u ) body }

@ take_body ( Vec Slot ) t i k i c → ( Vec u ) {
    : ( Vec u ) b0 ( vec_new [u] )
    ( vec_push [u] b0 # u 5 )
    : ~ Slot s @ Slot { 1 b0 }
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
