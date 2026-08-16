// borrow_escape_join.nu — a stack reference riding a `?` / `??` JOIN
// (docs/MEMORY.md §2.3).
//
// Reference-ness propagated through closure literals, aggregate
// literals, copies and `=` assignments — but not through the phi of a
// conditional. So `^ f` was an error and `^ ? c f f` compiled clean,
// which is the same program with a branch that cannot change the
// answer: both arms hand the caller a pointer into the frame that is
// about to disappear. Every spelling below was confirmed
// stack-use-after-return under AddressSanitizer before the fix.
//
// The join publishes the DEEPEST live arm's referent depth: one arm
// carrying the reference is enough, because the result dangles on that
// path. An arm that returns never reaches the phi and was already
// checked at its own `^`.

$ `stdlib/core/vec.nu`

: Counter { i n i max }
: Slot { ( @ v ) cb }

// POSITIVE — the reference leaves through a ternary's phi.
@ ret_via_ternary → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ? > . c n 0 f f
}

// POSITIVE — same through a match's phi.
@ ret_via_match → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ?? . c n { 0 → f _ → f }
}

// POSITIVE — the join is bound to a local first. The binding inherits
// the depth exactly as `: ( @ v ) t f` does.
@ ret_via_bound_join → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    : ( @ v ) t ? > . c n 0 f f
    ^ t
}

// POSITIVE — the join feeds an aggregate literal's field, and the
// aggregate is what leaves.
@ ret_struct_of_join → Slot {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ @ Slot { ? > . c n 0 f f }
}

// POSITIVE — a non-return §2.3 sink: the join goes into a heap
// container, which outlives the frame just as a caller does.
@ join_into_heap ( Vec Slot ) heap → v {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ( vec_push [Slot] heap @ Slot { ? > . c n 0 f f } )
}

// CONTROL — a helper that merely INVOKES the closure retains nothing,
// so handing it a join of stack references is correct code.
@ run ( @ v ) cb → v { ( cb ) }

@ join_into_invoker → i {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ( run ? > . c n 0 f f )
    ^ . c n
}

// CONTROL — a join between two closures that capture NOTHING is not a
// stack reference, and returning it is ordinary code.
@ no_escape_plain_join → ( @ v ) {
    : i k 1
    ^ ? > k 0 \ → v {} \ → v {}
}

// CONTROL — the join stays inside the frame it references. Nothing
// outlives anything, so no diagnostic may fire.
@ no_escape_local_join → i {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    : ( @ v ) g ? > . c n 0 f f
    ( g )
    ^ . c n
}

@ main → i {
    : ( @ v ) _a ( ret_via_ternary )
    : ( @ v ) _b ( ret_via_match )
    : ( @ v ) _c ( ret_via_bound_join )
    : Slot _d ( ret_struct_of_join )
    : ( Vec Slot ) heap ( vec_new [Slot] )
    ( join_into_heap heap )
    ( vec_free [Slot] heap )
    : i _g ( join_into_invoker )
    : ( @ v ) _e ( no_escape_plain_join )
    : i _f ( no_escape_local_join )
    ^ 0
}
