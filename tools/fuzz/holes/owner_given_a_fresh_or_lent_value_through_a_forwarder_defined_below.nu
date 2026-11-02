// owner_given_a_fresh_or_lent_value_through_a_forwarder_defined_below: agora #375 — an owner given what a forwarder of a function hands back: a fresh value on some runs, a lend on others. The forwarder answered "lent" on every run, so each fresh value leaked, in both definition orders (the forwarder defined below its caller).
// Closed: while a forwarder's lend summary may still grow, an argument the lend cannot come out of counts as no owner of `o`'s: a scalar parameter is skipped, a field path is its root binding, an alias is the owners it aliases (__lend_from_other_owners, __lend_owner_other); and `^ ( g x )` hands back g's own per-call ownership answer, not false where g may lend (gen_ret; agora #375).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | - | agora #375: an owner given what a forwarder of a function hands back, defined below
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → ?String {
    ^ @ ?String { T ( string_from `a fresh string long enough for the heap` ) }
}

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ~ ? String o ( make )
    = o ( fwdm vs 1 )
    = o ( fwdm vs 0 )
    = o ( fwdm vs 1 )
    = o ( fwdm vs 1 )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}

@ maybe ( Vec String ) v i w → ?String {
    ? == w 0 { ^ ( vec_get [String] v 0 ) } { ^ ( make ) }
}

@ fwdm ( Vec String ) v i w → ?String { ^ ( maybe v w ) }
