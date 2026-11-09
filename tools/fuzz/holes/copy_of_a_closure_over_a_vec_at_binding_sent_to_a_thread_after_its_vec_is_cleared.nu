// copy_of_a_closure_over_a_vec_at_binding_sent_to_a_thread_after_its_vec_is_cleared: agora #483 — a copy of a closure over a `vec_at` binding (`: b2 body`) handed to a thread after the Vec was cleared
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a copy of a closure over a vec_at binding sent to a thread after its Vec is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string cleared before the thread that holds its handle runs` ) )
    : ~ ( @ v ) b2 \ → v {}
    {
        : String e ( vec_at [String] t 0 )
        : ( @ v ) body \ → v { ( nurl_println ( string_data e ) ) }
        = b2 body
    }
    ( vec_clear [String] t )
    ?? ( thread_spawn b2 ) { T th → { ( thread_join th ) } F _ → {} }
    ^ 0
}
