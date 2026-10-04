// borrow_match_arm_double_free.nu — a double free written inside a `??` arm
// is a compile error, like the same code anywhere else.
//
// The borrow checker rejected this shape inside a `?` arm, a `~` loop, a
// foreach body, a bare `{ }` block, a helper, a generic body, a trait method
// and a defer — but not inside a `??` arm, where it compiled clean and
// segfaulted in the allocator at run time (confirmed under AddressSanitizer).
//
// The reason was principled: a `??` arm binds payload variables (`T v → …`)
// that have no `let` row, so descending into an arm with the outer, flat
// name-keyed state would conflate an arm's `v` with a same-named binding
// outside and report a bug that is not one. The whole match was therefore a
// state-preserving black box.
//
// The conflation is avoidable without scope-qualified state: each arm binds
// its payload names (carried on its `match-arm-edge` row) for the arm's
// extent only, and on the way out they — and every binding the arm declared —
// are put back to their outer state. An arm's `v` never speaks for an outer
// `v`, and what an arm does to a genuinely outer binding now reaches the
// code after the match (borrow_match_arm_outer_double_free).

// POSITIVE below: two arm-local aliases of one Vec, both freed, in an arm of
// a match used as a statement and in one used as a value.
//
// CONTROL: an arm that reads its payload binding and an outer binding by the
// same name as another arm's — the shape the black box existed to protect —
// and an arm that frees an arm-local Vec exactly once. Neither may warn.

$ `stdlib/core/vec.nu`

: | Sel { SA i SB i SC }

@ control ( Vec i ) outer → i {
    : Sel s @ Sel { SA 1 }
    // Payload `v` in two arms, and an outer binding also named `v` in scope
    // — nothing here is a violation and nothing may be reported.
    : i v 7
    ^ ?? s {
        SA v → + v ( vec_len [i] outer )
        SB v → { : ( Vec i ) local ( vec_new [i] )
            : i n + v ( vec_len [i] local )
            ( vec_free [i] local )
            n }
        SC → v
    }
}

@ main → i {
    : ( Vec i ) keep ( vec_new [i] )
    ( vec_push [i] keep 1 )
    ( nurl_print ( nurl_str_int ( control keep ) ) )

    : Sel s @ Sel { SA 1 }

    // POSITIVE — match as a statement.
    ?? s {
        SA n → { : ( Vec i ) a ( vec_new [i] )
            : ( Vec i ) b a
            ( vec_free [i] a )
            ( vec_free [i] b )
            n }
        SB n → n
        SC → 0
    }

    // POSITIVE — match as a value.
    : i r ?? s {
        SA n → { : ( Vec i ) c ( vec_new [i] )
            : ( Vec i ) d c
            ( vec_free [i] c )
            ( vec_free [i] d )
            n }
        SB n → n
        SC → 0
    }
    ( nurl_print ( nurl_str_int r ) )

    ( vec_free [i] keep )
    ^ 0
}
