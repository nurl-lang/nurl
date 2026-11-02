// owner_given_a_lend_of_an_alias_through_a_forwarder_defined_above: agora #375 — an owner given what a forwarder lends out of an alias of a local Vec: the alias was no owner to the check, and o's old value leaked (the forwarder defined above its caller).
// Closed: while a forwarder's lend summary may still grow, an argument the lend cannot come out of counts as no owner of `o`'s: a scalar parameter is skipped, a field path is its root binding, an alias is the owners it aliases (__lend_from_other_owners, __lend_owner_other); and `^ ( g x )` hands back g's own per-call ownership answer, not false where g may lend (gen_ret; agora #375).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | - | agora #375: an owner given what a forwarder lends out of an alias of a local Vec, defined above
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → ?String {
    ^ @ ?String { T ( string_from `a fresh string long enough for the heap` ) }
}

@ first ( Vec String ) v → ?String {
    ^ ( vec_get [String] v 0 )
}

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ( Vec String ) al vs
    : ~ ? String o ( make )
    = o ( first al )
    = o ( first al )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
