// map: §2.1 | A2 | rejected | - | AGORA-939: an inout parameter's field taken by a sink that may panic
// AGORA-939 (closed): refused - the sink takes the field as the call starts, so a panic in it hands `h` back to a `recover`ing caller with `buf` empty (github#2110 head 9e025429: accepted, a SEGV after recover)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v i k → i {
    ? > k 2 { ( panic `in the sink` ) } {}
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
