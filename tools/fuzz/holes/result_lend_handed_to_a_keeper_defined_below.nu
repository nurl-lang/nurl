// result_lend_handed_to_a_keeper_defined_below: agora #459 — `( unr ( maybr o 0 ) )`, `unr` taking its `!String E` over, defined below its caller
// Closed: a call's result that lends on some runs, handed to a callee not compiled yet, is copied on those runs where the callee takes it over (consume_flag, agora #459).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.6 | A2 | runs-clean | - | agora #459: a result lent to a keeper defined below
$ `stdlib/core/string.nu`
$ `stdlib/core/result.nu`

: | E { Bad }

@ mkr s t → !String E { ^ @ !String E { T ( string_from t ) } }

@ maybr ! String E a i k → !String E { ? == k 0 { ^ a } {} ^ ( mkr `a fresh result long enough for the heap here` ) }

@ main → i {
    : !String E o ( mkr `the owner long enough for the heap here` )
    : String s ( unr ( maybr o 0 ) )
    ( nurl_println ( string_data s ) )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F _ → {} }
    ^ 0
}

@ unr ! String E r → String { ^ ?? r { T v → v F _ → ( string_from `bad` ) } }
