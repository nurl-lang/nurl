// Test: owned-slice ownership across REASSIGNMENT (`=`), the assignment dual
// of the `?`/`??` binding fixes.
//   * `= rs <fresh ? / ?? slice>` frees the old backing buffer before the
//     store (rule-3 dual, previously only recognised a `[ … ]` literal RHS
//     syntactically, so a ternary/match RHS leaked the old buffer).
//   * `= dst src` with a bare-identifier RHS MOVES src's slice into dst and
//     un-registers src, so the buffer is freed exactly once — previously both
//     freed it (a double-free that SIGABRTs, which this test's EXIT-0 golden
//     catches even without a sanitizer).
// Values flow through acc so a wrong result also flags a regression; --san
// (leak detection) proves the freed-old-buffer side of the reassign fixes.

@ main → i {
    : ~ i acc 0

    // reassign with a fresh ternary RHS: frees the old [1 2 3], stores [10 20]
    : b c T
    : ~ rs [i | 1 2 3]
    = rs ? c [i | 10 20] [i | 30 40]
    : *i p . rs 0
    = acc + acc . p 0  // +10

    // reassign with a fresh match RHS: frees the [10 20], stores [7 7]
    : ?i o @ ?i { T 5 }
    = rs ?? o { T v → [i | 7 7] F → [i | 9 9] }
    : *i p2 . rs 0
    = acc + acc . p2 0  // +7

    // bare-identifier slice MOVE: zs's buffer goes to ys, freed once (a
    // double-free here aborts the process → non-zero exit → golden mismatch)
    : ~ ys [i | 100 200]
    : zs [i | 3 4]
    = ys zs
    : *i p3 . ys 0
    = acc + acc . p3 0  // +3

    // 10 + 7 + 3 = 20
    ( nurl_print ( nurl_str_int acc ) )
    ( nurl_print `\n` )
    ^ 0
}
