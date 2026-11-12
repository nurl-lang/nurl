// field_of_a_parameter_or_fresh_string_bound_by_a_new_name_runs_clean: agora #739 — `@ pk1 L1 x b c → String { ? c { ^ . x s } {} ^ ( mks ) }` bound by a new name: the fresh String leaked
// Closed: as for agora #625 — a lend of a parameter's field or part beside a fresh value answers per call (__hown_mixed); a temporary of a type with a `% Drop` of its own handed back whole on some runs is dropped on the runs the call's answer says its result is its own (agora #739, #457).
// main b64e33a1: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #739: `@ pk1 L1 x b c → String { ? c { ^ . x s } {} ^ ( mks ) }` bound by a new name: the fresh String leaked
$ `stdlib/core/string.nu`

: L1 { String s }

@ mks → String { ^ ( string_from `a fresh string long enough for the heap here` ) }

@ mk1 → L1 { ^ @ L1 { ( mks ) } }

@ pk1 L1 x b c → String { ? c { ^ . x s } {} ^ ( mks ) }

@ run b c → i {
    : L1 e1 ( mk1 )
    : String o ( pk1 e1 c )
    ( nurl_println ( string_data o ) )
    ^ 0
}

@ main → i {
    ( run F )
    ( run T )
    ^ 0
}
