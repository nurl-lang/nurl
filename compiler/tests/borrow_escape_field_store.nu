// borrow_escape_field_store.nu — a stack reference written into a
// longer-lived struct's FIELD (docs/MEMORY.md §2.3).
//
// `= holder f` (whole binding) has been checked since the region
// analysis landed; `= . holder cb f` was not, so the reference walked
// into a struct that outlives the block it points into, and returning
// that struct handed the caller a pointer to the dead frame —
// confirmed stack-use-after-return under AddressSanitizer.
//
// The field store has the same two effects the whole-binding form has:
// the struct INHERITS the reference (so a later `^ holder` fires) and a
// store into a struct declared in a shallower region is reported at the
// store itself.

: Counter { i n i max }
: Slot { ( @ v ) cb }

// POSITIVE — `box` lives at the function body (depth 1); `c` and the
// closure over it live inside the `?` block (depth 2). The store makes
// `box` outlive its referent.
@ leak_via_field_store → v {
    : ~ Slot box @ Slot { \ → v {} }
    ? > 1 0 {
        : ~ Counter c @ Counter { 0 10 }
        : ( @ v ) f \ → v { = . c n + . c n 1 }
        = . box cb f
    } {}
    : ( @ v ) g . box cb
    ( g )
}

// POSITIVE — same region, so the store itself is silent; what the store
// does is make `box` a stack reference, and RETURNING it dangles.
@ ret_after_field_store → Slot {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    : ~ Slot box @ Slot { \ → v {} }
    = . box cb f
    ^ box
}

// CONTROL — the struct and the referent share a region and the struct
// never leaves the frame. Flagging this would be a false positive.
@ no_escape_same_region_field → i {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    : ~ Slot box @ Slot { \ → v {} }
    = . box cb f
    : ( @ v ) g . box cb
    ( g )
    ^ . c n
}

// CONTROL — an ordinary scalar field store carries no reference at all.
@ no_escape_scalar_field → i {
    : ~ Counter c @ Counter { 0 10 }
    = . c n 7
    ^ . c n
}

@ main → i {
    ( leak_via_field_store )
    : Slot _a ( ret_after_field_store )
    : i _b ( no_escape_same_region_field )
    : i _c ( no_escape_scalar_field )
    ^ 0
}
