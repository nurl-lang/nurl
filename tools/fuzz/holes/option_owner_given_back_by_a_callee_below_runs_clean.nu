// option_owner_given_back_by_a_callee_below_runs_clean: `= o ( pickb o other k )` with `pickb` defined below the call.
// Guard for agora #427: runs clean on main by the module-end lend answers (#410, #742) and the per-call keys.
// map: §7.6 | A2 | runs-clean | - | agora #427 guard: an option owner given back by a callee below
$ `stdlib/core/string.nu`

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pickb o other 1 )
    ( show o )
    = o ( pickb o other 0 )
    ( show o )
    ^ 0
}

@ pickb ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }
