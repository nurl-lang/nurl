// map: §2.11 | A2 | rejected | - | agora #864: a closure assigns its borrowed struct parameter over a by-pointer capture; run by a callee with a local of its own, the capture borrows a released value
$ `stdlib/core/vec.nu`

: Resp { i status ( Vec u ) body }

@ mk i st → Resp {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 65 )
    ( vec_push [u] b # u 66 )
    ^ @ Resp { st b }
}

@ once ( @ v Resp ) f → v {
    : Resp tmp ( mk 9 )
    ( f tmp )
}

@ borrowed → i {
    : ~ Resp best ( mk 0 )
    ( once \ Resp r → v { ? > . r status . best status { = best r } {} } )
    ^ + . best status ( vec_len [u] . best body )
}

@ main → i {
    ( nurl_print_int ( borrowed ) ) ( nurl_print `\n` )
    ^ 0
}
