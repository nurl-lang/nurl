// map: §2.1 | A2 | runs-clean | - | AGORA-952: a closure released while an inout field is taken, from a maker that does not take the `% Drop` value over
// AGORA-952 (closed): the guard - mkf releases `d` itself and hands back a closure over nothing of it (no `retcap`), so releasing the closure runs no drop
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: D { i n }

% Drop D { @ drop D c → v { ? > . c n 2 { ( panic `in drop` ) } {} } }

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ mk i d → ( Vec u ) { ^ ( vec_new [u] ) }

@ mkf sink D d → ( @ i ) {
    : i n . d n
    ^ \ → i { ^ 7 }
}

@ cycle inout Holder h i k → v {
    : ~ ( @ i ) f ( mkf @ D { k } )
    : ( @ i ) g ( mkf @ D { 1 } )
    : i n ( take . h buf )
    = f g
    = . h buf ( mk n )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
