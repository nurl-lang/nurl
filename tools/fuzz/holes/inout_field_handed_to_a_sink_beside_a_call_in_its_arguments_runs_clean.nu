// map: §2.1 | A2 | runs-clean | - | AGORA-939 guard: a call in a sink's own arguments runs before the sink is handed the field
// AGORA-939 guard: `g` runs while `. h buf` is still the holder's, so it is no panic point for the take - accepted, and runs clean
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v i k → i { ^ ( vec_len [u] v ) }

@ g i k → i { ^ + k 1 }

@ cycle inout Holder h i k → v {
    : i n ( take . h buf ( g k ) )
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( cycle h 3 )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
