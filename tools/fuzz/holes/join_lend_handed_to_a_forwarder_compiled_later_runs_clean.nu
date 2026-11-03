// join_lend_handed_to_a_forwarder_compiled_later_runs_clean: agora #459 — `( gfw [String] ? c ( maybe o 0 ) ( maybe p 0 ) d )`, a `?` join whose arms lend, handed to a forwarder not compiled yet that takes it over
// Guard: a join that lends, handed to a callee whose summaries are not final, is copied on the paths it lends where the callee takes it over (consume_flag), as a call's result is (agora #459).
// main: runs clean (base 8a2afbc3).
// map: §7.6 | A2 | runs-clean | - | agora #459: guard, a join lent to a forwarder compiled later
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ maybe ? String a i k → ?String { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ sho ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ ug [A] ? A o A d → A { ^ ?? o { T v → v F → d } }

@ peek ? String o → i { ?? o { T s → { ^ ( string_len s ) } F → { ^ 0 } } }

@ gfw [A] ? A o A d → A { : A x ( ug [A] o d ) ^ x }

@ main → i {
    : ?String o ( mk `the owner long enough for the heap here` )
    : ?String p ( mk `the second owner long enough for heap` )
    : String a ( ug [String] ( maybe o 1 ) ( string_from `a default long enough for the heap here` ) )
    : b c == ( peek o ) 39
    : String x ( gfw [String] ? c ( maybe o 0 ) ( maybe p 0 ) ( string_from `a second default long enough for the heap` ) )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data x ) )
    ( sho o )
    ( sho p )
    ^ 0
}
