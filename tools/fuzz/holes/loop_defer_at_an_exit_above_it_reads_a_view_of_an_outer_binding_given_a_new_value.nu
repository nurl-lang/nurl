// loop_defer_at_an_exit_above_it_reads_a_view_of_an_outer_binding_given_a_new_value: `: ~ String x …  ~ c { = x ( new )  ? d { ^ 1 } {}  : s v ( string_data x )  ; { ( nurl_println v ) } }`.
// Closed: rejected. A `^` above a loop body's `;` runs that defer from the second round on (an earlier round armed it, agora #670); there `v` still holds the earlier round's view, of the value of `x` this round's `=` released. The walk carries the defer's kept bindings across the back-edge with what they borrow.
// main 0b3f239: accepted; it ran clean only because the `^` skipped the defer (#670's wrong output). With the defer run there and the walk unchanged: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #670: a `^` above a loop body's `;` runs the defer with an earlier round's view of an outer binding this round gave a new value
$ `stdlib/core/string.nu`

@ mk i k → String { : ~ String r ( string_from `x: a loop string long enough for a heap buffer ` ) ( string_push_int r k ) ^ r }

@ f i d → i {
    : ~ String x ( mk 0 )
    : ~ i k 0
    ~ < k 3 {
        = x ( mk k )
        ? == k d { ^ 1 } {}
        : s v ( string_data x )
        ; { ( nurl_println v ) }
        = k + k 1
    }
    ^ 0
}

@ main → i {
    ( nurl_println_int ( f 1 ) )
    ^ 0
}
