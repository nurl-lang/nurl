// option_owner_given_back_a_pick_ten_calls_deep_runs_clean: `= o ( id ( id … ( pick o other k ) … ) )`: the pick ten calls deep
// AGORA-966 guard (AGORA-946 D4a): accepted and runs clean - the nested call's result is a fresh value; A2 (tools/ncore) accepts it, and the run-time identity test keeps the owner's old value where it comes back (agora #410, #427, #438). Only the direct `= o ( pick o other k )` is refused.
// map: §7.6 | A2 | runs-clean | - | AGORA-966 (AGORA-946 D4a): `= o ( id ( id … ( pick o other k ) … ) )`: the pick ten calls deep
$ `stdlib/core/string.nu`

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ id ? String a → ?String { ^ a }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( id ( id ( id ( id ( id ( id ( id ( id ( id ( id ( pick o other 1 ) ) ) ) ) ) ) ) ) ) )
    ( show o )
    = o ( id ( id ( id ( id ( id ( id ( id ( id ( id ( id ( pick o other 0 ) ) ) ) ) ) ) ) ) ) )
    ( show o )
    ( show other )
    ^ 0
}
