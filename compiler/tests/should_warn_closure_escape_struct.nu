// should_warn_closure_escape_struct.nu — closure-escape detection must
// see through a struct wrapper.
//
// docs/GOTCHAS.md item 5 / item 8: a closure that captures a
// `: ~`-mutable multi-field struct is captured BY POINTER into the
// enclosing frame. The existing escape check warns when such a
// closure is returned directly (`^ closure`). Before this fix, putting
// the closure into a struct literal first (`@ Slot { cb }`) and then
// returning the STRUCT silently passed the check — the
// `__captures_byref` taint was not propagated through `gen_agg_lit`.
//
// Fix: gen_agg_lit now sets `__last_closure_byref__` when any field of
// the aggregate is a byref-capturing closure (literal or binding), so
// the struct binding inherits `<name>__captures_byref` and the
// `^`-return / escape-call checks fire as they do for a bare closure.
//
// One positive case (warns) + one negative control (no warning).

: Counter { i n  i max }
: Slot    { ( @ v ) cb }

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
