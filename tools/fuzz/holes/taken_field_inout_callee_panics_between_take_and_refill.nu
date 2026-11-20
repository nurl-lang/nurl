// map: §2.1 | A2 | rejected | - | AGORA-929: an `inout` callee panics between a sink's take of `. h buf` and its refill, under `recover`
// AGORA-929 (this shape, closed): refused - a call that may panic while an inout parameter's field is taken (main 08e56f54: accepted, a null handle after recover)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    ? > k 2 { ( panic `unwind` ) } {}
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
