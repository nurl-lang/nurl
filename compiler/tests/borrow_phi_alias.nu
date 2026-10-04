// borrow_phi_alias.nu — the ownership/phi aggressor: a handle
// reaching a new binding through a value-producing `?` whose OTHER arm
// is a fresh allocation.
//
//     : ( Vec i ) chosen ? flag a ( make )
//     : i n ( consume [i] chosen )      // consume frees chosen
//     ( vec_free [i] a )                // second free when flag holds
//
// Confirmed under ASan before the fix: SEGV inside free, reached from
// vec_free via _nurl_main. It compiled clean in BOTH modes, because the
// `?` result's provenance was never tracked — the checker saw `chosen`
// and `a` as two unrelated owners.
//
// Reported by default (it used to be --strict-borrowck only): `a` and
// `chosen` are alias partners on the path where the `?` selected `a`, so
// consuming `chosen` leaves `a` maybe-freed there, and freeing it again is
// the double free (docs/MEMORY.md §2.1). Only that path counts: CONTROL 2,
// freeing whichever binding the `?` did NOT select, is not flagged.
//
// One positive + two controls.

$ `stdlib/core/vec.nu`

@ consume [T] ( Vec T ) v → i {
    : i n ( vec_len [T] v )
    ( vec_free [T] v )
    ^ n
}

@ make → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 42 )
    ^ v
}

@ main → i {
    // CONTROL 1 — both arms allocate. The result belongs to `owned`
    // alone, and freeing it is the only correct thing to do.
    : i flag 1
    : ( Vec i ) owned ? > flag 0 ( make ) ( make )
    : i m ( consume [i] owned )
    ? > m 99 { ( nurl_print `many\n` ) } {}

    // POSITIVE — the true arm hands `a`'s handle to `chosen`, which
    // `consume` then frees. The free below is the second one.
    : ( Vec i ) a ( make )
    : ( Vec i ) chosen ? > flag 0 a ( make )
    : i n ( consume [i] chosen )
    ( vec_free [i] a )
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print `\n` )

    ^ 0
}
