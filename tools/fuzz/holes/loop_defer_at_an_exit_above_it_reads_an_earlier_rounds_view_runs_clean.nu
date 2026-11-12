// loop_defer_at_an_exit_above_it_reads_an_earlier_rounds_view_runs_clean: `~ c { ? d { ^ 1 } {}  : String x …  : s v ( string_data x )  ; { ( nurl_println v ) } }`, and an outer owner read the same way.
// Closed: runs clean, and must stay so. A `^` above a loop body's `;` runs that defer from the second round on (agora #670), with the earlier round's `v`: a view of that round's `x`, which codegen keeps to the cleanup (agora #655) — the round's own `x` and `v` are bound below the `^`, and a later round binding the names again changes nothing the defer reads.
// main 0b3f239: accepted; ran clean, but the `^` skipped the defer (#670's wrong output).
// map: §2.10 | A2 | runs-clean | - | agora #670: a `^` above a loop body's `;` runs the defer with an earlier round's view of that round's binding, and with an outer owner nothing changes
$ `stdlib/core/string.nu`

@ mk i k → String { : ~ String r ( string_from `x: a loop string long enough for a heap buffer ` ) ( string_push_int r k ) ^ r }

@ f i d → i {
    : String o ( mk 100 )
    : ~ i k 0
    ~ < k 3 {
        ? == k d { ^ 1 } {}
        : String x ( mk k )
        : s v ( string_data x )
        ; { ( nurl_println v ) ( nurl_println ( string_data o ) ) }
        = k + k 1
    }
    ^ 0
}

@ main → i {
    ( nurl_println_int ( f 2 ) )
    ( nurl_println_int ( f 9 ) )
    ^ 0
}
