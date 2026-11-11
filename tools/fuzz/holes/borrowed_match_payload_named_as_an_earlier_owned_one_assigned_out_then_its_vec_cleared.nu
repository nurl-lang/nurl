// borrowed_match_payload_named_as_an_earlier_owned_one_assigned_out_then_its_vec_cleared: agora #703 — `?? ( mko 7 ) { T v → … }` then `?? ( vec_get [S] va 0 ) { T v → { = keep v } }`, `( vec_clear [S] va )`, `keep` read
// The guard of the #703 fix: a fresh payload starts with no borrow relation, and a lent one gets its own — an earlier owned payload of the name does not make it an owner.
// main a013bfae9: refused; stays refused.
// map: §2.2 | A2 | rejected | - | agora #703 guard: a borrowed `??` payload named as an earlier owned one is assigned to an outer binding, the Vec cleared, the binding read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks i k → S {
    ^ @ S { ( string_from `an owned value long enough for a heap buffer` ) k }
}

@ mko i k → ?S {
    ^ @ ?S { T ( mks k ) }
}

@ main → i {
    : ~ ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va ( mks 1 ) )
    : ~ i t 0
    ?? ( mko 7 ) { T v → { = t . v n } F → {} }
    : ~ S keep ( mks 0 )
    ?? ( vec_get [S] va 0 ) { T v → { = keep v } F → {} }
    ( vec_clear [S] va )
    ( nurl_println ( string_data . keep name ) )
    ^ - t 7
}
