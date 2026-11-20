// map: §2.1 | A2 | rejected | - | AGORA-939: a refill by an instance of a generic function that may panic
// AGORA-939 (closed): refused - the instance `mk [u]` may panic (github#2110 head 9e025429: accepted)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ mk [T] i k → ( Vec T ) {
    ? > k 2 { ( panic `unwind` ) } {}
    ^ ( vec_new [T] )
}

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    = . h buf ( mk [u] k )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
