// map: §2.1 | A2 | rejected | - | AGORA-939: an inout parameter's field in a binding that also aliases a local's, handed to a keeper that may panic
// AGORA-939 (closed): refused - with a local's part in its alias set the value is taken, not copied, so `keep` takes `. h buf` as the call starts and a panic hands `h` back to a `recover`ing caller with it empty (CodeRabbit on github#2129: ncore accepted)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ keep sink ( Vec u ) v i k → ( Vec u ) {
    ? > k 2 { ( panic `in the keeper` ) } {}
    ^ v
}

@ cycle inout Holder h i k → v {
    : Holder l @ Holder { ( vec_new [u] ) }
    : ( Vec u ) b ? > k 0 . h buf . l buf
    : ( Vec u ) w ( keep b k )
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
