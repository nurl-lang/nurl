// Test: a `:` binding whose RHS is a `??` match with FRESH owned-slice arms
// must register the binding as the slice's owner — the same ownership-through-
// control-flow gap fixed for the `?` ternary (gen_cond), now for gen_match.
// Match arms are STATEMENTS (blocks), so the fix relies on gen_stmt resetting
// the fresh-owned-slice flag at every statement boundary: a block arm's value
// is its trailing expression, never a slice literal bound earlier inside it.
//
// Values are read back through acc so a premature free (UAF / double-free)
// shows as a wrong sum or a crash; --san proves the leak side (each fresh-
// slice match used to leak its buffer at function exit).

@ main → i {
    : ~ i acc 0

    // Some → T-arm, a fresh slice literal
    : ?i o1 @ ?i { T 5 }
    : r1 ?? o1 { T v → [i | 1 2 3] F → [i | 40 50 60] }
    : *i p1 . r1 0
    = acc + acc . p1 0  // +1

    // None → F-arm, element 2
    : ?i o2 @ ?i { F }
    : r2 ?? o2 { T v → [i | 4 5 6] F → [i | 7 8 9] }
    : *i p2 . r2 0
    = acc + acc . p2 2  // +9

    // block arm whose VALUE is a fresh literal (flag must survive the block,
    // and NOT be confused with a slice literal bound earlier in the block)
    : r3 ?? o1 { T v → { : ~ i z + v 15 [i | z z] } F → [i | 0] }
    : *i p3 . r3 0
    = acc + acc . p3 0  // +20

    // 1 + 9 + 20 = 30
    ( nurl_print ( nurl_str_int acc ) )
    ( nurl_print `\n` )
    ^ 0
}
