// closure_over_a_vec_at_binding_sent_to_a_thread_after_its_vec_is_cleared: agora #483 — the closure binding holds the element's handle until `thread_spawn` copies it; the Vec is cleared before the spawn
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a vec_at binding sent to a thread after its Vec is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string cleared before the thread that holds its handle runs` ) )
    : ~ ( @ v ) body \ → v {}
    {
        : String e ( vec_at [String] t 0 )
        = body \ → v { ( nurl_println ( string_data e ) ) }
    }
    ( vec_clear [String] t )
    ?? ( thread_spawn body ) { T th → { ( thread_join th ) } F _ → {} }
    ^ 0
}
