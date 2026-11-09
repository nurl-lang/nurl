// closure_over_a_vec_at_binding_written_as_the_spawn_argument_after_its_vec_is_cleared: agora #483 — a closure over `e = ( vec_at t 0 )`, written as `thread_spawn`'s argument after `t` was cleared
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a vec_at binding written as the spawn argument after its Vec is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    : String e ( vec_at [String] t 0 )
    : ( @ v ) body \ → v { ( nurl_println ( string_data e ) ) }
    : ~ ( @ v ) b2 body
    ( vec_clear [String] t )
    ?? ( thread_spawn b2 ) { T th → { ( thread_join th ) } F _ → {} }
    ^ 0
}
