// borrow_strict_ret_alias.nu — the interprocedural form: a helper that
// may hand one of its ARGUMENTS' handles back as its result.
//
//     @ pick ( Vec i ) a i f → ( Vec i ) { ^ ? f a ( vec_new [i] ) }
//     : ( Vec i ) c ( pick a 1 )
//     ( vec_free [i] c ) ( vec_free [i] a )     // same buffer twice
//
// The checker already had a returned-parameter summary, but it answers
// a different question: §2.8 asks whether the result may be a STACK
// REFERENCE, and drives refdepth propagation. This needs the ownership
// question — may the result BE one of the arguments' heap handles —
// which is recorded in its own summary (g_fn_ret_alias) so no escape
// diagnostic moves. It is fed by `^ p` and, through the same phi
// provenance the `?` case uses, by `^ ? c p ( fresh )`.
//
// Always conditional, never definite: the summary says the handle MAY
// come back, so this is strict-only like its intraprocedural twin.
//
// One positive + two controls.

$ `stdlib/core/vec.nu`

// May return its first argument's handle.
@ pick ( Vec i ) a i f → ( Vec i ) {
    ^ ? > f 0 a ( vec_new [i] )
}

// Returns a FRESH Vec on every path — no argument handle escapes.
@ fresh_of ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    ( vec_push [i] out ( vec_len [i] a ) )
    ^ out
}

@ main → i {
    // CONTROL 1 — the callee returns a fresh Vec, so `c1` and `s` are
    // separate owners and both frees are right.
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s 3 )
    : ( Vec i ) c1 ( fresh_of s )
    ( vec_free [i] c1 )
    ( vec_free [i] s )

    // CONTROL 2 — `pick` may return `b`'s handle, and the code frees
    // only the result. Handing a handle over is not itself an error.
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 4 )
    : ( Vec i ) c2 ( pick b 1 )
    ( vec_free [i] c2 )

    // POSITIVE — `pick` may return `a`'s handle, and both are freed.
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 5 )
    : ( Vec i ) c3 ( pick a 1 )
    ( vec_free [i] c3 )
    ( vec_free [i] a )

    ^ 0
}
