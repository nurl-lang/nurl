// param_field_shadow.nu — regression for gotcha #10.
//
// When a function parameter has the same name as a destination struct
// field, `= . obj field val` (where field == param name == value name)
// previously miscompiled to a single-index GEP using the value as the
// array index, dropping the actual field offset. Fixed 2026-05-17 in
// gen_field_store: a param-named IDENT that also matches a field now
// routes to the field-store path; non-param locals (vec.nu's loop
// counters like `len` / `idx` / `i`, which coincide with field names
// in other structs) still route to the array-store path.

: Box {
    i cap
    i len
}

@ box_set_both i cap i len → *Box {
    : *Box b # *Box ( nurl_alloc Z Box )
    // The bug shape: param name == field name. Pre-fix this miscompiled.
    = . b cap cap
    = . b len len
    ^ b
}

@ box_get_cap *Box b → i { ^ . b cap }
@ box_get_len *Box b → i { ^ . b len }

@ box_free *Box b → v { ( nurl_free # s b ) }

// Negative control: variable-index array store on a *Match-like pointer
// must still work. The Vec[A] vec_push pattern (`= . data len x` where
// `len` is a loop index that happens to share a name with a struct
// field) depends on this routing.
: Pt { i x i y }

@ pt_fill *Pt arr i n → v {
    : ~ i len 0  // local index var; NOT a param
    ~ < len n {
        // Pt has field `x` and `y` — neither matches `len`, so this is
        // unambiguous. But also exercise the case where the index var
        // shadows a field name from a DIFFERENT struct (here `len`
        // overlaps with Box.len). The param-shadow rule keys on the
        // *current scope's* params, so this stays an array store.
        = . arr len @ Pt { len * len 10 }
        = len + len 1
    }
}

@ main → i {
    // ── gotcha-10 positive case ─────────────────────────────────
    : *Box b ( box_set_both 99 7 )
    ( nurl_print `box.cap=` ) ( nurl_print ( nurl_str_int ( box_get_cap b ) ) ) ( nurl_print `\n` )
    ( nurl_print `box.len=` ) ( nurl_print ( nurl_str_int ( box_get_len b ) ) ) ( nurl_print `\n` )
    ( box_free b )

    // ── negative control: array store with index var still routes
    //    via the array path, not the field path ─────────────────
    : *Pt arr # *Pt ( nurl_alloc * 3 Z Pt )
    ( pt_fill arr 3 )
    : ~ i k 0
    ~ < k 3 {
        : Pt cur . arr k
        ( nurl_print `pt.x=` ) ( nurl_print ( nurl_str_int . cur x ) )
        ( nurl_print ` pt.y=` ) ( nurl_print ( nurl_str_int . cur y ) ) ( nurl_print `\n` )
        = k + k 1
    }
    ( nurl_free # s arr )

    ^ 0
}
