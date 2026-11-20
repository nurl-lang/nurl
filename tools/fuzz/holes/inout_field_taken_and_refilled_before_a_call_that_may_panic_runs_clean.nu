// inout_field_taken_and_refilled_before_a_call_that_may_panic_runs_clean: AGORA-929 guard — an `inout` callee takes `. h buf` by a sink and gives it a value made before the take (no call between the take and the store) before a call that may panic, under `recover`: accepted
// map: §2.1 | A2 | runs-clean | - | AGORA-929 guard: an inout parameter's taken field refilled before a call that may panic
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ check i k → v { ? > k 2 { ( panic `unwind` ) } {} }

@ cycle inout Holder h i k → v {
    : ( Vec u ) fresh ( vec_new [u] )
    : i n ( take . h buf )
    = . h buf fresh
    ( check k )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ( nurl_println_int ( vec_len [u] . h buf ) )
    ^ 0
}
