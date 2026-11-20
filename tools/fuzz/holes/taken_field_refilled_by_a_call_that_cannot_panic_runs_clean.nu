// map: §2.1 | A2 | runs-clean | - | AGORA-939 guard: a refill whose callee cannot panic
// AGORA-939 guard: `make_buf` builds a Vec and can't panic, so the refill is the caller's own - accepted, and runs clean after recover
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ make_buf i k → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u k )
    ^ v
}

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    = . h buf ( make_buf k )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ - ( vec_len [u] . h buf ) 2
}
