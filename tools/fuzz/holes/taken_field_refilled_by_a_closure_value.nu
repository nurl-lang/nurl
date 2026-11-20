// map: §2.1 | A2 | rejected | - | AGORA-939: a refill made by calling a closure value
// AGORA-939 (closed): refused - a closure value's body is not known by name, so its call may panic (github#2110 head 9e025429: accepted)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ cycle inout Holder h ( @ ( Vec u ) ) f → v {
    : i n ( take . h buf )
    = . h buf ( f )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : !v PanicInfo r ( recover \ → v { ( cycle h \ → ( Vec u ) { ( panic `x` ) ^ ( vec_new [u] ) } ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
