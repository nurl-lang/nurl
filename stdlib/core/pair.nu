// stdlib/core/pair.nu — generic Pair[A B]
//
// Pair[A B] is a value-type aggregate of two heterogeneous fields.
// Unlike Vec / HashMap / String, Pair has NO heap allocation of its
// own — the struct is passed by value, so the storage of the Pair
// itself is wherever the caller chose to put it (alloca, struct field
// of an outer aggregate, return slot, …). Field ownership is not
// tracked by the compiler for tparam-typed fields, so the caller must
// drop owned fields manually (or use pair_free_with).
//
// API:
//   ( pair_new      [A B] a b )            → ( Pair A B )
//   ( pair_first    [A B] p )              → A    borrowed view
//   ( pair_second   [A B] p )              → B    borrowed view
//   ( pair_eq       [A B] a b eq_a eq_b )  → b    closure-based equality
//   ( pair_free_with [A B] p drop_a drop_b ) → v
//   ( pair_free_a   [A B] p drop_a )       → v    drop only first
//   ( pair_free_b   [A B] p drop_b )       → v    drop only second
//
// MEMORY (LLM-friendly summary):
//
//   * Pair[i i], Pair[s i] (s = borrowed raw string), Pair[b f] etc.
//     — TRIVIAL.  No drop needed.
//
//   * Pair[String i] / Pair[i ( Vec X )] — one field is OWNED.
//     Use pair_free_a / pair_free_b passing the right per-field drop
//     (string_free, \ A x → v { ( vec_free [A] x ) } …).
//
//   * Pair[String String] etc. — both owned.
//     Use pair_free_with passing two drop closures.
//
//   * Pair inside Vec[Pair[A B]] — every element shares the rule of
//     its A and B.  Use vec_free_with passing a closure that calls
//     pair_free_with (or the bare pair drop if both fields are
//     trivial).
//
// CONSTRUCTORS THAT RETURN A PAIR (e.g. iter_zip, iter_enumerate,
// map_iter) PRESERVE THEIR SOURCE'S OWNERSHIP:  the Pair fields are
// aliases of source elements unless the caller explicitly clones.
// In iterator pipelines that materialise via iter_collect, the
// resulting ( Vec ( Pair A B ) ) borrows the upstream sources — do
// NOT drop the upstream Vec/HashMap and the collected Vec
// independently when A or B is owned.

: Pair [A B] { A first B second }

@ pair_new [A B] A first B second → ( Pair A B ) {
    ^ @ ( Pair A B ) { first second }
}

@ pair_first [A B] ( Pair A B ) p → A {
    ^ . p first
}

@ pair_second [A B] ( Pair A B ) p → B {
    ^ . p second
}

@ pair_eq [A B] ( Pair A B ) a ( Pair A B ) b ( @ b A A ) eq_a ( @ b B B ) eq_b → b {
    ? ! ( eq_a . a first . b first ) { ^ F } {}
    ^ ( eq_b . a second . b second )
}

@ pair_free_with [A B] ( Pair A B ) p ( @ v A ) drop_a ( @ v B ) drop_b → v {
    ( drop_a . p first )
    ( drop_b . p second )
}

@ pair_free_a [A B] ( Pair A B ) p ( @ v A ) drop_a → v {
    ( drop_a . p first )
}

@ pair_free_b [A B] ( Pair A B ) p ( @ v B ) drop_b → v {
    ( drop_b . p second )
}
