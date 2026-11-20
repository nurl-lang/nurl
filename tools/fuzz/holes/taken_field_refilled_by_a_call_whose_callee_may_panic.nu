// map: §2.1 | A2 | rejected | - | AGORA-939: a refill whose callee calls a function that may panic
// AGORA-939 (closed): refused - the refill's callee may panic through a function it calls (github#2110 head 9e025429: accepted)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ boom i k → v { ? > k 2 { ( panic `unwind` ) } {} }

@ make_buf i k → ( Vec u ) {
    ( boom k )
    ^ ( vec_new [u] )
}

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    = . h buf ( make_buf k )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
