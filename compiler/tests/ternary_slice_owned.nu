// Test: a `:` binding whose RHS is a `?` ternary with FRESH owned-slice arms
// (slice literals, or a nested ternary that is itself fresh) must register the
// binding as the slice's owner — otherwise the buffer leaks at function exit.
// The syntactic TT_LBRACK check can't see the literal through the `?`, so
// gen_slice_literal/gen_cond forward a `__last_slice_owned__` provenance flag
// that the binding consumes (both the inference and annotated-type paths).
//
// Values are read back through acc so a premature free (UAF / double-free)
// shows as a wrong sum or a crash even without ASan; the suite's --san build
// proves the leak side (this used to leak 24 B per fresh-slice ternary).

@ main → i {
    : ~ i acc 0

    // then-branch taken: [1 2 3], element 0
    : b c1 T
    : r1 ? c1 [i | 1 2 3] [i | 40 50 60]
    : *i p1 . r1 0
    = acc + acc . p1 0                        // +1

    // else-branch taken: [7 8 9], element 2
    : b c2 F
    : r2 ? c2 [i | 4 5 6] [i | 7 8 9]
    : *i p2 . r2 0
    = acc + acc . p2 2                        // +9

    // nested ternary: the else-arm is itself a fresh-slice `?`
    : b a F
    : b b2 T
    : r3 ? a [i | 100] ? b2 [i | 20 21] [i | 30]
    : *i p3 . r3 0
    = acc + acc . p3 1                        // +21

    // annotated-type binding path
    : [i r4 ? c1 [i | 2 2] [i | 3 3]
    : *i p4 . r4 0
    = acc + acc . p4 0                        // +2

    // still owned across later statements → freed exactly once at fn exit
    : r5 ? c1 [i | 11 12] [i | 13 14]
    : *i p5 . r5 0
    = acc + acc . p5 0                        // +11

    // 1 + 9 + 21 + 2 + 11 = 44
    ( nurl_print ( nurl_str_int acc ) )
    ( nurl_print `\n` )
    ^ 0
}
