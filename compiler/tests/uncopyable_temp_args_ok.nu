// A temporary that cannot be copied (a `% Drop` value with no clone)
// handed straight to a call is dropped after it — read, discarded, nested —
// or moves into the result when the callee hands it back, also through a
// generic (h234). Each `Res` prints `drop` once.
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

@ mkr → Res {
    ^ @ Res { ( vec_new [i] ) }
}

@ look Res r → i {
    ^ ( vec_len [i] . r buf )
}

@ id Res r → Res {
    ^ r
}

@ idt [T] T x → T {
    ^ x
}

@ main → i {
    ( nurl_println_int ( look ( mkr ) ) )
    ( id ( mkr ) )
    : Res a ( id ( mkr ) )
    ( nurl_println_int ( look ( id ( mkr ) ) ) )
    : Res b ( idt [Res] ( mkr ) )
    : ( Rc Res ) c ( rc_new [Res] ( id ( mkr ) ) )
    ( nurl_println_int ( vec_len [i] . a buf ) )
    ^ 0
}
