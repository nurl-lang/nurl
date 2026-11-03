// option_temporary_not_handed_back_on_some_runs: agora #457 — `( maybe ( mk … ) 1 )` with `maybe ?String a i k → ?String`: a fresh option handed back instead
// Closed: an option or result temporary the callee may hand back whole is released after the call on the runs whose per-call answer says the result is the callee's own; on the runs it lends, it is the result (agora #457).
// main: LeakSanitizer reported the temporary's payload (base 1abc8111).
// map: §7.2 | A2 | runs-clean | - | agora #457: `( maybe ( mk … ) 1 )` with `maybe ?String a i k → ?String`: a fresh option handed back instead
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ maybe ? String a i k → ?String { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ?String x ( maybe ( mk `a temporary long enough for the heap` ) 1 )
    ( show x )
    ^ 0
}
