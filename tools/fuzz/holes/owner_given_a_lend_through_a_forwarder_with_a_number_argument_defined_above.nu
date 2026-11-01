// owner_given_a_lend_through_a_forwarder_with_a_number_argument_defined_above: agora #375 — a `: ~ ?String` owner given, again and again, what a two-level forwarder lends out of one of two local Vecs, chosen by a number argument: o's old value was kept back and leaked when the forwarder was defined above its caller (the forwarder defined above its caller).
// Closed: while a forwarder's lend summary may still grow, an argument the lend cannot come out of counts as no owner of `o`'s: a scalar parameter is skipped, a field path is its root binding, an alias is the owners it aliases (__lend_from_other_owners, __lend_owner_other); and `^ ( g x )` hands back g's own per-call ownership answer, not false where g may lend (gen_ret; agora #375).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | - | agora #375: a `, defined above
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → ?String {
    ^ @ ?String { T ( string_from `a fresh string long enough for the heap` ) }
}

@ pick2 ( Vec String ) a ( Vec String ) b i w → ?String {
    ? == w 0 { ^ ( vec_get [String] a 0 ) } { ^ ( vec_get [String] b 0 ) }
}

@ fwd2 ( Vec String ) a ( Vec String ) b i w → ?String { ^ ( pick2 a b w ) }

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ( Vec String ) ws ( vec_new [String] )
    ( vec_push [String] ws ( string_from `another element string long enough for the heap` ) )
    : ~ ? String o ( make )
    = o ( fwd2 vs ws 1 )
    = o ( fwd2 vs ws 0 )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
