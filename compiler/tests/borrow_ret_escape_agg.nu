// Borrow checker — return escape through an aggregate field
// (docs/MEMORY.md §2.8). `wrap` embeds its closure parameter `cb` as a
// field of the `Slot` it returns, so the checker records param 0 in
// g_fn_ret_param[wrap] just as a bare `^ cb` would. At `( wrap f )` the
// returned Slot therefore carries `f`'s referent depth — and `f`
// captures a `: ~`-mutable Counter BY POINTER (a stack reference into
// `caller`). Returning that Slot from `caller` dangles the captured
// slot. The aggregate hides the reference from a per-function pass; the
// returned-parameter summary surfaces it.
: Counter { i n i max }
: Slot { ( @ v ) cb }

@ wrap ( @ v ) cb → Slot {
    ^ @ Slot { cb }
}

@ caller → Slot {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( wrap f )
}

@ main → i {
    : Slot s ( caller )
    ^ 0
}
