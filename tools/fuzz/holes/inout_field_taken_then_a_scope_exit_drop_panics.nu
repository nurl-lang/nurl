// map: §2.1 | A2 | rejected | - | AGORA-942: a binding whose `% Drop` may panic goes out of scope between an inout parameter's take and refill
// AGORA-942 (closed): refused - the inner block's `t` is released at its end, before the refill; its destructor may panic (main 3f08626b: accepted, a SEGV after recover)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: D { i n }

% Drop D { @ drop D c → v { ? > . c n 2 { ( panic `in drop` ) } {} } }

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ mk i d → ( Vec u ) { ^ ( vec_new [u] ) }

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    { : D t @ D { k } }
    = . h buf ( mk n )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
