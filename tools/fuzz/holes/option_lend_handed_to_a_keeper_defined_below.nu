// option_lend_handed_to_a_keeper_defined_below: agora #459 — `( unwrap_or ( maybe o 0 ) d )` with `unwrap_or`, which takes its option over, defined below its caller
// Closed: whether a callee not compiled yet takes the argument over is a module-end fact (consume_flag): a call's result that lends on some runs is copied on those runs where it does (agora #459). The same callee defined above was handed a copy already.
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.6 | A2 | runs-clean | - | agora #459: a lend handed to a keeper defined below
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ maybe ? String a i k → ?String { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ sho ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ?String o ( mk `the owner long enough for the heap here` )
    : String d ( string_from `a default long enough for the heap here` )
    : String s ( unwrap_or ( maybe o 0 ) d )
    ( nurl_println ( string_data s ) )
    ( sho o )
    ^ 0
}

@ unwrap_or ? String o String d → String { ^ ?? o { T v → v F → d } }
