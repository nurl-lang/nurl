// borrow_phi_alias_definite.nu — a value-producing `?` can SELECT a
// handle, and when every live arm selects the SAME one the result IS
// that handle on every path. That is an ordinary move, so the default
// checker reports the later free as a use-after-move.
//
// Only the syntactic form `: T b a` was ever recorded as an alias move,
// so a handle reaching a new binding through a phi was an ownership
// blind spot: both names then looked like sole owners and freeing both
// compiled clean.
//
// One positive + two controls that must stay silent.

$ `stdlib/core/vec.nu`

@ main → i {
    // CONTROL 1 — neither arm is a bare binding, so the result is a
    // fresh Vec that nothing else owns. Freeing it is right.
    : i flag 1
    : ( Vec i ) fresh ? > flag 0 ( vec_new [i] ) ( vec_new [i] )
    ( vec_free [i] fresh )

    // CONTROL 2 — the `?` selects a SCALAR, not a handle. Nothing is
    // aliased and `n` stays readable and freeable through its owner.
    : ( Vec i ) src ( vec_new [i] )
    ( vec_push [i] src 5 )
    : i n ? > flag 0 ( vec_len [i] src ) 0
    ? > n 99 { ( nurl_print `many\n` ) } {}
    ( vec_free [i] src )

    // POSITIVE — both arms are `a`, so `chosen` is `a` on every path.
    // `a` is moved; the second free is the same buffer twice.
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    : ( Vec i ) chosen ? > flag 0 a a
    ( vec_free [i] chosen )
    ( vec_free [i] a )

    ^ 0
}
