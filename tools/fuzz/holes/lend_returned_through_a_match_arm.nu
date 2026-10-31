// lend_returned_through_a_match_arm: a function that returns a call's lend through a `??` arm (`^ ?? ( slot_of k ) { T s → ( vec_get v s ) … }`) was not summarised as lending `v`: the join's arms did not say what they lend, only the scrutinee's payloads did. The caller took the payload for its own and released it — the Vec's own element.
// Closed: a join's lending arm records the call it ends in (mem_arm_call_lend), and returning the join records what that call lends, as the scrutinee's (mem_ret_param_lend_via) — the function lends `v`, and releasing the payload is rejected. A payload of an option a call answers per run is handed to a consumer as a copy on the runs it was lent (__lent_by_call).
// main (before this PR): AddressSanitizer reported heap-use-after-free reading the element after the release.
// map: §7.6 | A2 | rejected | h311 | a function returning a call's lend through a ?? arm was not summarised as lending; the caller released the payload — the Vec's own element (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ slot_of s key → ?i { ? == ( nurl_str_len key ) 1 { ^ @ ?i { T 0 } } {} ^ @ ?i { F } }

@ get ( Vec String ) v s key → ?String {
    ^ ?? ( slot_of key ) {
        T sl → ( vec_get [String] v sl )
        F _ → @ ?String { F }
    }
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `alpha` ) )
    ?? ( get v `a` ) { T x → { ( string_free x ) } F → {} }
    ( nurl_println ( string_data ( vec_at [String] v 0 ) ) )
    ^ 0
}
