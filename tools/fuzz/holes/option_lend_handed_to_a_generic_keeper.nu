// option_lend_handed_to_a_generic_keeper: agora #459 — `( unwrap_or [String] ( maybe o 0 ) d )`, a generic `unwrap_or` that takes its option over, handed a call's result that is `o`'s own value on that run
// Closed: a call's result that may lend, handed to a callee whose summaries are not final at the call (a generic instance, a callee defined below, a library function compiled later), is copied on the runs it lends where the callee takes it over — a module-end fact (consume_flag), as for a callee compiled above (agora #459).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.6 | A2 | runs-clean | - | agora #459: a lend handed to a generic keeper
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ maybe ? String a i k → ?String { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ sho ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ unwrap_or [A] ? A o A d → A { ^ ?? o { T v → v F → d } }

@ main → i {
    : ?String o ( mk `the owner long enough for the heap here` )
    : String d ( string_from `a default long enough for the heap here` )
    : String s ( unwrap_or [String] ( maybe o 0 ) d )
    ( nurl_println ( string_data s ) )
    ( sho o )
    ^ 0
}
