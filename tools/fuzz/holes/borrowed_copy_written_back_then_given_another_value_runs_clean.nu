// borrowed_copy_written_back_then_given_another_value_runs_clean: `: ~ Slot s ( vec_at [Slot] t k )  : ( Vec u ) out . s body  = . s body ( vec_new )  ( put_slot t k s )  = s ( vec_at [Slot] t 0 )  ( put_slot t 0 s )` - here the copy is written back first, then given another value and written back again
// AGORA-870 guard (CodeRabbit on github#1959): accepted - each copy goes back to its slot before the next
// map: §7.6 | A2 | runs-clean | - | AGORA-870
$ `stdlib/core/vec.nu`

: Slot { i id ( Vec u ) body }

// (unsafe: vec_put_back is the raw write-back protocol; take_body itself is safe code)
unsafe @ put_slot ( Vec Slot ) t i k Slot s → v { ( vec_put_back [Slot] t k s ) }

@ take_body ( Vec Slot ) t i k i c → ( Vec u ) {
    : ~ Slot s ( vec_at [Slot] t k )
    : ( Vec u ) out . s body
    = . s body ( vec_new [u] )
    ( put_slot t k s )
    = s ( vec_at [Slot] t 0 )
    ( put_slot t 0 s )
    ^ out
}

@ main → i {
    : ( Vec Slot ) t ( vec_new [Slot] )
    : ( Vec u ) b ( vec_new [u] ) ( vec_push [u] b # u 7 ) ( vec_push [u] b # u 8 )
    ( vec_push [Slot] t @ Slot { 1 b } )
    : ( Vec u ) b2 ( vec_new [u] ) ( vec_push [u] b2 # u 5 ) ( vec_push [u] b2 # u 6 )
    ( vec_push [Slot] t @ Slot { 2 b2 } )
    : ( Vec u ) got ( take_body t 1 1 )
    ( vec_push [u] got # u 9 )
    ^ ( vec_len [u] got )
}
