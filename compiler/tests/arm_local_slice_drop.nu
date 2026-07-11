// Test: Phase 2D arm-local fall-through drop for OWNED SLICES (memory-
// model rule 5). A slice literal `:`-bound inside a ? / ?? / while /
// foreach arm that falls through must be freed at arm end — these used
// to leak because `__owned_slices__` is scope-shadowed and the arm's
// delta died unseen at nurl_sym_pop (found by ASan in packages/gguf).
// Also covers the rule 3 dual (`= xs [ … ]` frees the old backing
// buffer) and the alias hazard the fix must NOT introduce: an
// `= outer [ … ]` inside an arm registers an OUTER binding, which must
// survive the arm's fall-through — only bindings DECLARED during the
// arm are dropped there (driven by the `__slice_decls__` delta).
// Values are asserted through acc so a premature free (UAF) or a skip
// shows up as a wrong sum even without ASan; run the suite's san build
// to prove the leak side.

@ main → i {
    : ~ i acc 0

    // ? arm, inferred let — freed at the arm's fall-through
    ? 1 {
        : xs [i | 1 2 3]
        : *i p . xs 0
        = acc . p 0
        ( nurl_print `then-arm ok\n` )
    } {}

    // ?? arm, annotated let — same
    : ?i o @ ?i { T 5 }
    ?? o {
        T v → {
            : [i ys [i | 4 5]
            : *i q . ys 0
            = acc + acc + . q 0 v
            ( nurl_print `match-arm ok\n` )
        }
        F → {}
    }

    // while body — freed once per iteration (a leak would be 10×)
    : ~ i k 0
    ~ < k 10 {
        : zs [i | 7 8 9]
        : *i r . zs 0
        = acc + acc . r 2
        = k + k 1
    }

    // foreach body — same per-iteration drop
    : ws [i | 1 2]
    ~ w ws {
        : vs [i | 6]
        : *i s2 . vs 0
        = acc + acc . s2 0
    }

    // rule 3: reassignment with a fresh literal frees the OLD buffer
    : ~ rs [i | 10 20]
    = rs [i | 30 40 50]
    : *i rp . rs 0
    = acc + acc . rp 0

    // arm-reassign of an OUTER binding: the new buffer must survive the
    // arm (reading it later would UAF if the arm dropped it)
    ? 1 { = rs [i | 7] } {}
    : *i up . rs 0
    = acc + acc . up 0

    // 1 + 9 + 90 + 12 + 30 + 7 = 149
    ( nurl_print ( nurl_str_int acc ) )
    ( nurl_print `\n` )
    ^ 0
}
