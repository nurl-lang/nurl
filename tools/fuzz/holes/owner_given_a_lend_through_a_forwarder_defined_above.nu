// owner_given_a_lend_through_a_forwarder_defined_above: agora #344 — a `: ~ ?String` owner given a lend through a user callee compiled BEFORE its caller (`= o ( first vs )`, first forwarding vec_get's lend) kept its old value back and leaked it: the callee's lend summary was not final yet, so the assignment could not tell the lend came from another owner.
// Closed: while a callee's lend summary may still grow (retfwd), every argument must be an owner other than the binding assigned, whatever positions the final summary names; then the old value goes by its flag (__lend_from_other_owners, agora #344).
// main: accepted; LeakSanitizer reported 88 bytes leaked.
// map: §7.6 | A2 | runs-clean | - | agora #344: an owner given a lend through a forwarder compiled before its caller
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ make → ?String {
    ^ @ ?String { T ( string_from `a fresh string long enough for the heap` ) }
}

@ first ( Vec String ) v → ?String {
    ^ ( vec_get [String] v 0 )
}

@ pick i k → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ~ ? String o ( make )
    ? == k 2 { = o ( first vs ) } {}
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}

@ main → i {
    ( pick 1 )
    ( pick 2 )
    ^ 0
}
