// inout_holder_given_a_callee_local_view_then_a_try_exit_in_a_loop: agora #379 — as inout_holder_given_a_callee_local_view_then_a_try_exit, the \ inside a loop
// Closed: the tryret row inside a loop is checked on every walk of the body (agora #379).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #379: as inout_holder_given_a_callee_local_view_then_a_try_exit, the \ inside a loop
$ `stdlib/core/string.nu`

: | E { Bad }

: W { s v }

@ may i k → !i E {
    ? == k 1 { ^ @ !i E { F Bad } } {}
    ^ @ !i E { T k }
}

@ fill inout W w → !i E {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    : ~ i n 0
    ~ < n 3 {
        = w @ W { ( string_data b ) }
        : i x \ ( may n )
        = w @ W { `literal` }
        = n + n 1
    }
    ^ @ !i E { T 0 }
}

@ main → i {
    : ~ W w @ W { `literal` }
    ?? ( fill w ) { T _ → {} F _ → {} }
    ( nurl_println . w v )
    ^ 0
}
