// map: §2.1 | A2 | rejected | - | AGORA-952: an inout field a sink took, then a block's end releases a closure whose environment took over a value whose `% Drop` may panic
// AGORA-952 (closed): refused - `f` goes out of scope before the refill and its environment's `D` drop may panic; the function has no borrow, so the scope's end is asked for it (main 3f08626b: accepted, a SEGV after recover)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: D { i n }

% Drop D { @ drop D c → v { ? > . c n 2 { ( panic `in drop` ) } {} } }

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ mk i d → ( Vec u ) { ^ ( vec_new [u] ) }

@ mkf sink D d → ( @ i ) { ^ \ → i { ^ . d n } }

@ cycle inout Holder h i k → v {
    : ~ i n 0
    {
        : ( @ i ) f ( mkf @ D { k } )
        = n ( take . h buf )
    }
    = . h buf ( mk n )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
