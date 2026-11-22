// map: §2.1 | A2 | rejected | - | AGORA-952: a closure binding handed to a wrapper that takes it over, released by '=' while an inout field is taken
// AGORA-952 (closed): refused - `f0`'s environment, taken over by `wrap`, holds mkf's `D`, whose drop may panic (main 3f08626b: accepted, a SEGV after recover)
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
    : ( @ i ) f0 ( mkf @ D { k } )
    : ~ ( @ i ) f ( wrap f0 )
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
