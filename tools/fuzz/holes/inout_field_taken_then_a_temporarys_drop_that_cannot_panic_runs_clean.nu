// map: §2.1 | A2 | runs-clean | - | AGORA-942 guard: a temporary whose `% Drop` cannot panic, released between an inout parameter's take and refill
// AGORA-942 guard: the release is a point a panic may unwind from only when the destructor may panic - this one cannot, so it is accepted and runs clean
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: D { i n }

% Drop D { @ drop D c → v { ( nurl_println `dropped` ) } }

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ mk i d → ( Vec u ) { ^ ( vec_new [u] ) }

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    = . h buf ( mk . @ D { k } n )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
