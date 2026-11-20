// map: §2.1 | A2 | rejected | - | AGORA-939: an inout parameter's taken field refilled by a call that may panic
// AGORA-939 (closed): refused - the refill's own call runs before its store and may panic, so a `recover`ing caller would get `h` back with `buf` empty (github#2110 head 9e025429: accepted, a SEGV after recover)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ make_buf i k → ( Vec u ) {
    ? > k 2 { ( panic `unwind` ) } {}
    ^ ( vec_new [u] )
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
    ^ 0
}
