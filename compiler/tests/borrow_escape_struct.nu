// borrow_escape_struct.nu — escape analysis must see through a
// struct wrapper.
//
// docs/GOTCHAS.md item 5 / item 8: a closure that captures a
// `: ~`-mutable multi-field struct is captured BY POINTER into the
// enclosing frame. The escape check rejects returning such a closure
// directly (`^ closure`); it must also reject wrapping it in a struct
// literal first (`@ Slot { cb }`) and returning the STRUCT.
//
// gen_agg_lit carries the deepest field referent depth up to the
// aggregate (`__last_expr_refdepth__`), so a Slot holding a stack-
// reference closure is itself a stack reference and the `^`-return
// check fires exactly as it does for a bare closure.
//
// One positive case (warns) + one negative control (no warning).

: Counter { i n i max }
: Slot { ( @ v ) cb }

// POSITIVE — closure captures `c` byref, is wrapped in a Slot, and the
// Slot is returned. The captured pointer dangles once make_slot exits.
@ make_slot → Slot {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) bump \ → v {
        = . c n + . c n 1
    }
    : Slot s @ Slot { bump }
    ^ s
}

// CONTROL — the closure captures the Counter BY VALUE (immutable `:`,
// snapshotted into the env). Wrapping it in a Slot and returning that
// is safe; no warning must fire.
@ make_safe_slot → Slot {
    : Counter c @ Counter { 0 10 }
    : ( @ v ) bump \ → v {
        = . c n + . c n 1
    }
    : Slot s @ Slot { bump }
    ^ s
}

@ main → i {
    : Slot s1 ( make_slot )
    : ( @ v ) f1 . s1 cb
    ( f1 )
    : Slot s2 ( make_safe_slot )
    : ( @ v ) f2 . s2 cb
    ( f2 )
    ^ 0
}
