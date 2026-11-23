// option_owner_given_back_its_own_value_ten_calls_deep_runs_clean: `= o ( id ( id … ( id o ) … ) )`: a chain ten calls deep that lends only the owner
// AGORA-966 (AGORA-946 D4a): accepted at any depth - only the owner is lent, so the old value is what comes back (CodeRabbit on github#2226)
// map: §7.6 | A2 | runs-clean | - | AGORA-966 (AGORA-946 D4a): `= o ( id ( id … ( id o ) … ) )`: a chain ten calls deep that lends only the owner
$ `stdlib/core/string.nu`

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ id ? String a → ?String { ^ a }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( id ( id ( id ( id ( id ( id ( id ( id ( id ( id ( id o ) ) ) ) ) ) ) ) ) ) )
    ( show o )
    ( show other )
    ^ 0
}
