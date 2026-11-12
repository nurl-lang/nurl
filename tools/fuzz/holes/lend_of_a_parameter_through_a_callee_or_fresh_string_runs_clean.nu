// lend_of_a_parameter_through_a_callee_or_fresh_string_runs_clean: agora #739 — `@ f1 String p b c → String { ? c { ^ ( string_from … ) } {} ^ ( f0 p ) }`, f0 handing its parameter back: the fresh String leaked
// Closed: as for agora #625 — a lend of a parameter's field or part beside a fresh value answers per call (__hown_mixed); a temporary of a type with a `% Drop` of its own handed back whole on some runs is dropped on the runs the call's answer says its result is its own (agora #739, #457).
// main b64e33a1: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #739: `@ f1 String p b c → String { ? c { ^ ( string_from … ) } {} ^ ( f0 p ) }`, f0 handing its parameter back: the fresh String leaked
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f0 String p → String { ^ p }

@ f1 String p b c → String { ? c { ^ ( string_from `fresh one, long enough for the heap, really` ) } {} ^ ( f0 p ) }

@ run b c → v {
    : ~ String x ( string_from `a string long enough to live on the heap for sure` )
    : String s ( f1 x c )
    ( nurl_println ( string_data s ) )
    ( nurl_println ( string_data x ) )
}

@ main → i {
    ( run T )
    ( run F )
    ^ 0
}
