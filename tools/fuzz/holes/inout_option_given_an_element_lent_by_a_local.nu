// inout_option_given_an_element_lent_by_a_local: agora #343 — as inout_option_given_an_element_lent_by_a_borrowed_parameter, with vs a local of the callee
// Closed: an `inout` option of an owned value given a call's lend is compared with its old value by its payload's key at run time: the old value itself stays; a lend of anything else is copied in and the old value released in place (agora #343).
// main: refused by clang: `__dropifv_w__opt.String` was called and never defined (base 145095d9 too).
// map: §7.6 | A2 | runs-clean | - | agora #343: as inout_option_given_an_element_lent_by_a_borrowed_parameter, with vs a local of the callee
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ make → ?String {
    ^ @ ?String { T ( string_from `a fresh string long enough for the heap` ) }
}

@ put inout ? String o i k → v {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    ? == k 1 { = o ( vec_get [String] vs 0 ) } {}
}

@ main → i {
    : ~ ? String o ( make )
    ( put o 0 )
    ( put o 1 )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
