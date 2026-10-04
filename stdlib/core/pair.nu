// stdlib/core/pair.nu — generic Pair[A B]
//
// Pair[A B] is a value-type aggregate of two heterogeneous fields.
// Unlike Vec / HashMap / String, Pair has NO heap allocation of its
// own — the struct is passed by value, so the storage of the Pair
// itself is wherever the caller chose to put it (alloca, struct field
// of an outer aggregate, return slot, …). Its fields are owned like
// any struct's: a Pair[String String] binding drops both Strings at the
// end of its scope, a Vec of them drops every pair (docs/MEMORY.md §7.6).
//
// API:
//   ( pair_new      [A B] a b )            → ( Pair A B )
//   ( pair_first    [A B] p )              → A    borrowed view
//   ( pair_second   [A B] p )              → B    borrowed view
//   ( pair_eq       [A B] a b eq_a eq_b )  → b    closure-based equality
//   ( pair_free_with [A B] p look_a look_b ) → v  early release; each hook
//                                                 is lent its field first
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

// Early release with a last look: each hook is lent its field, then `p`
// goes as dropping it does. The hooks only borrow (see vec_free_with).
@ pair_free_with [A B] sink ( Pair A B ) p ( @ v A ) drop_a ( @ v B ) drop_b → v {
    ( drop_a . p first )
    ( drop_b . p second )
}
