// owner_given_a_lend_of_a_field_through_a_forwarder_defined_above: agora #375 — an owner given what a forwarder lends out of a struct's Vec field (`( first . bx items )`): the field path was no owner to the check, and o's old value leaked (the forwarder defined above its caller).
// Closed: while a forwarder's lend summary may still grow, an argument the lend cannot come out of counts as no owner of `o`'s: a scalar parameter is skipped, a field path is its root binding, an alias is the owners it aliases (__lend_from_other_owners, __lend_owner_other); and `^ ( g x )` hands back g's own per-call ownership answer, not false where g may lend (gen_ret; agora #375).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | - | agora #375: an owner given what a forwarder lends out of a struct's Vec field (`( first , defined above
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Box { ( Vec String ) items }

@ make → ?String {
    ^ @ ?String { T ( string_from `a fresh string long enough for the heap` ) }
}

@ first ( Vec String ) v → ?String {
    ^ ( vec_get [String] v 0 )
}

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : Box bx @ Box { vs }
    : ~ ? String o ( make )
    = o ( first . bx items )
    = o ( first . bx items )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
