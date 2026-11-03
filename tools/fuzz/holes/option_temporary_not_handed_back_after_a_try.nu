// option_temporary_not_handed_back_after_a_try: agora #457 — a callee that tries its `?String` parameter (`\ a`) and hands it back on one run, a fresh option on another, given a temporary
// Closed: an option or result temporary the callee may hand back whole is released after the call on the runs whose per-call answer says the result is the callee's own; on the runs it lends, it is the result (agora #457).
// main: LeakSanitizer reported the temporary's payload (base 1abc8111).
// map: §7.2 | A2 | runs-clean | - | agora #457: a callee that tries its `?String` parameter (`\ a`) and hands it back on one run, a fresh option on another, given a temporary
$ `stdlib/core/string.nu`

@ mk s t i k → ?String { ? == k 0 { ^ @ ?String { F } } {} ^ @ ?String { T ( string_from t ) } }

@ sh ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ g ? String a i k → ?String {
    : String s \ a
    ? == k 1 { ^ a } {}
    ^ @ ?String { T ( string_from `a fresh value long enough for the heap here` ) }
}

@ run i k → v {
    : ~ ? String o ( mk `the owner long enough for the heap here` k )
    : ?String x ( g o k )
    ( sh x )
    = o ( g o k )
    ( sh o )
    ( sh ( g ( mk `a temp long enough for the heap here` k ) k ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ( run 2 )
    ^ 0
}
