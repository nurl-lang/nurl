// map: §2.1 | A2 | rejected | - | adversarial: a helper that may panic between the take and the refill
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ check i k → v { ? > k 2 { ( panic `unwind` ) } {} }

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    ( check k )
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
