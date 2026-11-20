// taken_field_of_a_closures_inout_parameter_across_a_call_that_may_panic: AGORA-929 (CodeRabbit on github#2110) — a closure's own `inout` parameter has its field taken, then a call that may panic runs before the refill, in a function with no `inout` parameter of its own
// map: §2.1 | A2 | rejected | - | AGORA-929: a closure's inout parameter's taken field across a call that may panic
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ check i k → v { ? > k 2 { ( panic `unwind` ) } {} }

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : ( @ v inout Holder i ) g \ inout Holder x i k → v {
        : i n ( take . x buf )
        ( check k )
        = . x buf ( vec_new [u] )
    }
    : !v PanicInfo r ( recover \ → v { ( g h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
