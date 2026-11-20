// map: §2.1 | A2 | runs-clean | - | AGORA-939 guard: the documented refill idiom, `= . h buf ( vec_new [u] )`
// AGORA-939 guard: vec_new cannot panic, so the field is the caller's again once the statement ends - accepted, and runs clean after recover
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ boom i k → v { ? > k 2 { ( panic `later` ) } {} }

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    = . h buf ( vec_new [u] )
    ( boom k )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ - ( vec_len [u] . h buf ) 1
}
