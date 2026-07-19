// Test: Phase 2D arm-local fall-through drop when the arm's LAST
// statement is an ASSIGNMENT. `= x …` deliberately publishes the
// stored value's type (it feeds `?? r { F e → { = rc e } }`-shaped arm
// phis), so an arm ending in one is value-typed — and the old gate
// (`arm type == void`) then skipped every arm-local drop, leaking any
// owned raw string or slice declared in the arm. The gate is now
// mem_arm_drop_safe: void OR plain scalar (int/float/bool) arm values
// cannot reference arm-local heap memory (the phi carries a copy), so
// the drop fires. Pointer/slice/aggregate arm values stay conservative
// (leak-not-UAF) — `{ : xs [i | …] xs }` must NOT free xs.
//
// Values are asserted through acc so a premature free (UAF) shows as a
// wrong sum or a crash; the leak side is pinned by the LSan CI set.
// (Found via ASan on packages/nurllama's converter: an owned
// nurl_str_slice bound in a `?` arm whose trailing `??` published a
// bool leaked 6 allocations per conversion.)

$ `stdlib/core/string.nu`

@ maybe i k → !v String {
    ? < k 100 { ^ @ !v String { F ( string_from `nope` ) } } {}
    ^ @ !v String { T 0 }
}

@ main → i {
    : ~ i acc 0

    // ? arm: owned raw string (nurl_str_slice allocates) declared, arm
    // ends in an assignment (i64) — the buffer must be freed at the
    // arm's fall-through, AFTER the assignment read it.
    ? > acc -1 {
        : s t ( nurl_str_slice `hello` 0 5 )
        = acc + acc ( nurl_str_len t )
    } {}
    // acc = 5

    // ? arm: owned slice literal + a `??` whose F-arm assigns (the ??
    // then publishes a scalar, making the enclosing arm scalar-typed —
    // the exact shape that leaked in packages/nurllama's converter).
    : ~ b flag F
    ? > acc 0 {
        : xs [i | 10 20 30]
        : *i p . xs 0
        ?? ( maybe acc ) {
            T _ → {}
            F e → {
                ( string_free e )
                = flag T
            }
        }
        = acc + acc . p 1
    } {}
    // acc = 25

    // ?? arm ending in an assignment: same rule through gen_match.
    : ?i o @ ?i { T 7 }
    ?? o {
        T v → {
            : s m ( nurl_str_slice `world!!` 0 7 )
            = acc + acc + v ( nurl_str_len m )
        }
        F → {}
    }
    // acc = 25 + 7 + 7 = 39
    // (The conservative side — pointer/slice-valued arms must NOT drop —
    // is pinned by ternary_slice_owned / match_slice_owned.)

    ? flag {} { = acc 0 }
    ( nurl_print ( nurl_str_int acc ) )
    ( nurl_print `\n` )
    ^ 0
}
