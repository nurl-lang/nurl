// temporary_not_handed_back_by_a_callee_defined_below: agora #457 — the callee defined below its caller
// Closed: a temporary argument the callee may hand back whole is dropped after the call on the runs whose per-call answer says the result is the callee's own (it was not handed back); on the runs it lends, it is the result (agora #457).
// main: LeakSanitizer reported the temporary (base a2f0fdf7).
// map: §7.2 | A2 | runs-clean | - | agora #457: the callee defined below its caller
$ `stdlib/core/string.nu`

@ main → i {
    : String x ( later ( string_from `a temporary long enough for the heap` ) 1 )
    : String y ( later ( string_from `a temporary long enough for the heap` ) 0 )
    ( nurl_println ( string_data x ) ) ( nurl_println ( string_data y ) )
    ^ 0
}

@ later String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }
