// map: §2.1 | A2 | rejected | - | AGORA-939: an inout parameter's field taken through a binding that reads it, by a sink that may panic
// AGORA-939 (closed): refused - `take` takes `. h buf` through `b` (AGORA-929) as the call starts, so a panic in it hands `h` back to a `recover`ing caller with `buf` empty (CodeRabbit on github#2129; main dac13adc: accepted, a SEGV after recover)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v i k → i {
    ? > k 2 { ( panic `in the sink` ) } {}
    ^ ( vec_len [u] v )
}

@ cycle inout Holder h i k → v {
    : ( Vec u ) b . h buf
    : i n ( take b k )
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
