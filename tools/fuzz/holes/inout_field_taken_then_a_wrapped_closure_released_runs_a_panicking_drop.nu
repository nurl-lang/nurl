// map: §2.1 | A2 | rejected | - | AGORA-952: a closure a wrapper took over, from a maker that took over a value whose `% Drop` may panic, released by '=' while an inout field is taken
// AGORA-952 (closed): refused - `wrap` takes the closure over, so its environment holds mkf's `D` (main 3f08626b: accepted, a SEGV after recover)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: D { i n }

% Drop D { @ drop D c → v { ? > . c n 2 { ( panic `in drop` ) } {} } }

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ mk i d → ( Vec u ) { ^ ( vec_new [u] ) }

@ mkf sink D d → ( @ i ) { ^ \ → i { ^ . d n } }

@ wrap sink ( @ i ) c → ( @ i ) { ^ \ → i { ^ + 1 ( c ) } }

@ cycle inout Holder h i k → v {
    : ~ ( @ i ) f ( wrap ( mkf @ D { k } ) )
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
