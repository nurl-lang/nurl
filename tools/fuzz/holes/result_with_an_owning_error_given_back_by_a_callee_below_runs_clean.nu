// result_with_an_owning_error_given_back_by_a_callee_below_runs_clean: `= o ( f o k )` over a `!i String` that holds an error, with `f` defined below its caller, handing back its argument on one run and a fresh error or a number on another.
// Closed (agora #475): the keep rule asks whether the new value IS the old one by its key, and `__ud_keyable` asked an option's or a result's first side only. A result whose Ok is a number had no key, so `= o ( f o 1 )` released o's error while the new value still was it (heap-use-after-free). Either side that keys keys it now, as mem_ud_ident_key already did.
// map: §7.6 | A2 | runs-clean | - | agora #475: the keep rule for a result whose error owns a String beside a number
$ `stdlib/core/string.nu`

@ show ! i String o → v { ?? o { T n → { ( nurl_println_int n ) } F e → { ( nurl_println ( string_data e ) ) } } }

@ main → i {
    : ~ ! i String o @ !i String { F ( string_from `the owned error string, long enough for the heap` ) }
    = o ( f o 1 )
    ( show o )
    = o ( f o 0 )
    ( show o )
    = o ( g o 1 )
    ( show o )
    = o ( g o 0 )
    ( show o )
    : ~ ! i String p @ !i String { T 3 }
    = p ( f p 1 )
    = p ( f p 0 )
    = p ( f p 1 )
    ( show p )
    ^ 0
}

@ f ! i String o i k → !i String {
    ? == k 1 { ^ o } {}
    ^ @ !i String { F ( string_from `a fresh error string, long enough for the heap` ) }
}

@ g ! i String o i k → !i String {
    ? == k 1 { ^ o } {}
    ^ @ !i String { T 7 }
}
