// loop_defer_reads_a_view_of_an_outer_binding_given_a_new_value_after_the_loop: `: ~ String x …  ~ c { : s v ( string_data x )  ; { ( nurl_println v ) } }  = x ( new )`.
// Closed: rejected. The defer runs at the function's exit with the last round's `v`, a view of the value of `x` the `=` after the loop released. The walk carries the defer's kept bindings out of the loop with what they borrow (agora #670); before, a loop-local binding was dropped at the loop's exit, and the defer's replay at the exit read a name it no longer tracked.
// main 0b3f239: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #670: a loop defer reads the last round's view of an outer binding given a new value after the loop
$ `stdlib/core/string.nu`

@ mk i k → String { : ~ String r ( string_from `x: a loop string long enough for a heap buffer ` ) ( string_push_int r k ) ^ r }

@ f i n → i {
    : ~ String x ( mk 0 )
    : ~ i k 0
    ~ < k n {
        : s v ( string_data x )
        ; { ( nurl_println v ) }
        = k + k 1
    }
    = x ( mk 9 )
    ^ k
}

@ main → i {
    ( nurl_println_int ( f 2 ) )
    ^ 0
}
