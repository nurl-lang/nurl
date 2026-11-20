// map: §2.1 | A2 | runs-clean | - | AGORA-939 guard: an inout parameter's field taken through a binding that reads it, by a sink that cannot panic, then refilled
// AGORA-939 guard: the field is gone while `take` runs, but `take` cannot panic, so nothing hands `h` back empty - accepted, and runs clean
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v i k → i {
    ^ ( vec_len [u] v )
}

@ cycle inout Holder h i k → v {
    : ( Vec u ) b . h buf
    : i n ( take b k )
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( cycle h 3 )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
