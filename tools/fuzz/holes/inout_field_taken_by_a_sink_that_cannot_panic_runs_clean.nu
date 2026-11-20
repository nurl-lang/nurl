// map: §2.1 | A2 | runs-clean | - | AGORA-939 guard: an inout parameter's field taken by a sink that cannot panic, then refilled
// AGORA-939 guard: `take` cannot panic, so the field is gone only until the refill - accepted, and runs clean after recover
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v i k → i {

    ^ ( vec_len [u] v )
}

@ cycle inout Holder h i k → v {
    : i n ( take . h buf k )
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
