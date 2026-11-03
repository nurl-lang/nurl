// temporary_not_handed_back_by_nested_calls: agora #457 — `( maybe ( maybe ( string_from … ) 1 ) 0 )` and the other orders
// Closed: a temporary argument the callee may hand back whole is dropped after the call on the runs whose per-call answer says the result is the callee's own (it was not handed back); on the runs it lends, it is the result (agora #457).
// main: LeakSanitizer reported the temporary (base a2f0fdf7).
// map: §7.2 | A2 | runs-clean | - | agora #457: `( maybe ( maybe ( string_from … ) 1 ) 0 )` and the other orders
$ `stdlib/core/string.nu`

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ main → i {
    : String x ( maybe ( maybe ( string_from `a temporary long enough for the heap` ) 1 ) 0 )
    : String y ( maybe ( maybe ( string_from `a temporary long enough for the heap` ) 0 ) 1 )
    : String z ( maybe ( maybe ( string_from `a temporary long enough for the heap` ) 0 ) 0 )
    ( nurl_println ( string_data x ) ) ( nurl_println ( string_data y ) ) ( nurl_println ( string_data z ) )
    ^ 0
}
