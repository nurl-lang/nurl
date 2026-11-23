// option_owner_given_back_a_nested_pick_through_a_callee_below_runs_clean: `= o ( second o ( pick o other k ) )` with `second` and `pick` defined below the call
// AGORA-966 guard (AGORA-946 D4a): accepted and runs clean - the nested call's result is a fresh value; A2 (tools/ncore) accepts it, and the run-time identity test keeps the owner's old value where it comes back (agora #410, #427, #438). Only the direct `= o ( pick o other k )` is refused.
// map: §7.6 | A2 | runs-clean | - | AGORA-966 (AGORA-946 D4a): `= o ( second o ( pick o other k ) )` with `second` and `pick` defined below the call
$ `stdlib/core/string.nu`

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( second o ( pick o other 1 ) )
    ( show o )
    = o ( second o ( pick o other 0 ) )
    ( show o )
    ^ 0
}

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ second ? String a ? String b → ?String { ^ b }
