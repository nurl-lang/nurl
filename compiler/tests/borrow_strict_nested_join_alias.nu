// borrow_strict_nested_join_alias.nu — handle provenance through a
// join nested inside a `??` arm (docs/MEMORY.md §2.2).
//
// A `?` / `??` can SELECT a manually-managed handle, so the join
// publishes which bindings its result may have come from and the `:`
// that receives it records a (conditional) move. gen_cond has carried
// a nested join's candidates up since #899 — `? c ? c a ( make ) …`
// — but the `??` twin dropped them, so
//
//     : ( Vec i ) b ?? c { 1 → ? d a a  _ → ( vec_new [i] ) }
//
// handed `a`'s buffer to `b` with nothing recorded, and freeing both
// names compiled clean: a confirmed heap use-after-free under
// AddressSanitizer. The one-level spellings (`?? c { 1 → a … }`, and
// the mirror `? c ?? … ( vec_new )`) were already reported; only the
// nesting was missing, which is what makes it a coverage gap rather
// than a rule change.
//
// Conditional, so `--strict-borrowck`: the join MAY have selected `a`,
// and the default checker reports only definite faults (§6.3).

$ `stdlib/core/vec.nu`

// POSITIVE — a ternary nested in a match arm.
@ match_of_ternary → i {
    : ( Vec i ) a ( vec_new [i] )
    : i c 1
    : ( Vec i ) b ?? c { 1 → ? > c 0 a a _ → ( vec_new [i] ) }
    ( vec_free [i] b )
    ( vec_free [i] a )
    ^ 0
}

// POSITIVE — a match nested in a match arm. Same situation, one more
// level of braces.
@ match_of_match → i {
    : ( Vec i ) a ( vec_new [i] )
    : i c 1
    : ( Vec i ) b ?? c { 1 → ?? c { 1 → a _ → a } _ → ( vec_new [i] ) }
    ( vec_free [i] b )
    ( vec_free [i] a )
    ^ 0
}

// CONTROL — the join selects between two FRESH containers, so `b` owns
// its own buffer and freeing both names is correct.
@ no_alias_fresh_arms → i {
    : ( Vec i ) a ( vec_new [i] )
    : i c 1
    : ( Vec i ) b ?? c { 1 → ? > c 0 ( vec_new [i] ) ( vec_new [i] )
        _ → ( vec_new [i] ) }
    ( vec_free [i] b )
    ( vec_free [i] a )
    ^ 0
}

@ main → i {
    : i _a ( match_of_ternary )
    : i _b ( match_of_match )
    : i _c ( no_alias_fresh_arms )
    ^ 0
}
