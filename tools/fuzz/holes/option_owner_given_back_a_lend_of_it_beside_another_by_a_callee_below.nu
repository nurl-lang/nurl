// option_owner_given_back_a_lend_of_it_beside_another_by_a_callee_below: `= o ( pick ( id o ) other k )` with `pick` and `id` defined below the call
// AGORA-966 (AGORA-946 D4a): refused - the call may hand back the owner's own value or another one, which A2 refuses in every spelling; a nested call's lend was not followed (CodeRabbit on github#2226)
// map: §7.6 | A2 | rejected | - | AGORA-966 (AGORA-946 D4a): `= o ( pick ( id o ) other k )` with `pick` and `id` defined below the call
$ `stdlib/core/string.nu`

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pick ( id o ) other 1 )
    ( show o )
    = o ( pick ( id o ) other 0 )
    ( show o )
    ^ 0
}

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ id ? String a → ?String { ^ a }
