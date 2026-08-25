// borrow_closure_body_double_free.nu — a double free written inside a
// closure body is a compile error, like the same code anywhere else.
//
// The borrow checker rejected this shape inside a `?` arm, a `~` loop, a
// foreach body, a bare `{ }` block, a helper, a generic body, a trait method
// and a defer — but not inside a closure body, where it compiled clean and
// segfaulted in the allocator at run time (confirmed under AddressSanitizer).
//
// The cause was one flag doing two jobs. `g_bck_closure_depth != 0` meant
// both "this statement belongs to the closure, not to the enclosing
// function" — which is true, and what the capture and summary logic asks —
// and "record nothing at all", which switched the checker off entirely for
// everything written inside a closure.
//
// A closure body is its own function, so it now gets its own recording
// context and its own analyze pass: the enclosing function's capture state
// is saved, a fresh one started, the body recorded into it, walked, and the
// outer one put back. Its parameters seed the walk exactly as a function's
// do. A capture is deliberately not seeded — what a closure does to a
// captured handle is the enclosing frame's question, answered by the
// consumed-capture replay that was already there — so it starts Uninit and
// cannot be reported.
//
// POSITIVE below: two closure-local aliases of one Vec, both freed, in a
// `:`-bound closure and in an inline one passed to a call.
//
// CONTROL: a closure that allocates and frees exactly once; a closure whose
// parameter shares a name with an outer binding; and a closure that reads a
// captured handle without consuming it. None may warn.

$ `stdlib/core/vec.nu`

@ apply ( @ i i ) f i x → i { ^ ( f x ) }

@ control ( Vec i ) outer → i {
    : i n 3
    // A closure-local Vec, freed exactly once — no violation.
    : ( @ i i ) once \ i k → i {
        : ( Vec i ) local ( vec_new [i] )
        ( vec_push [i] local k )
        : i len ( vec_len [i] local )
        ( vec_free [i] local )
        ^ len
    }
    // A parameter named like the outer binding, plus a read of a capture.
    : ( @ i i ) shadow \ i n → i { ^ + n ( vec_len [i] outer ) }
    ^ + ( once n ) ( shadow n )
}

@ main → i {
    : ( Vec i ) keep ( vec_new [i] )
    ( vec_push [i] keep 1 )
    ( nurl_print ( nurl_str_int ( control keep ) ) )

    // POSITIVE — a `:`-bound closure.
    : ( @ i i ) bad \ i x → i {
        : ( Vec i ) a ( vec_new [i] )
        : ( Vec i ) b a
        ( vec_free [i] a )
        ( vec_free [i] b )
        ^ x
    }
    ( nurl_print ( nurl_str_int ( bad 1 ) ) )

    // POSITIVE — an inline closure passed straight to a call.
    ( nurl_print ( nurl_str_int ( apply \ i y → i {
        : ( Vec i ) c ( vec_new [i] )
        : ( Vec i ) d c
        ( vec_free [i] c )
        ( vec_free [i] d )
        ^ y
    } 2 ) ) )

    ( vec_free [i] keep )
    ^ 0
}
