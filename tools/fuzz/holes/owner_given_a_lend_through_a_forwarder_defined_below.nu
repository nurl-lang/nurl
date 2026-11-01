// owner_given_a_lend_through_a_forwarder_defined_below: agora #344 — the twin of owner_given_a_lend_through_a_forwarder_defined_above with the callee compiled AFTER its caller: clean before and after the fix, so the verdict no longer depends on the order of definitions.
// Closed: (a guard of the order: __lend_from_other_owners, agora #344).
// main: ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #344: twin with the forwarder compiled after its caller
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ make → ?String {
    ^ @ ?String { T ( string_from `a fresh string long enough for the heap` ) }
}

@ pick i k → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ~ ? String o ( make )
    ? == k 2 { = o ( first vs ) } {}
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}

@ first ( Vec String ) v → ?String {
    ^ ( vec_get [String] v 0 )
}

@ main → i {
    ( pick 1 )
    ( pick 2 )
    ^ 0
}
