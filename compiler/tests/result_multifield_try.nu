// Test: `\ ( fn → ! T E )` try-propagate where T is a multi-field
// struct (heap-boxed payload). Twin of result_multifield.nu which
// exercises construction + `??` match destructure. The `\` operator
// previously only reconstructed single-pointer-handle structs (Vec,
// String); multi-field heap-boxes fell through with type i64 and
// triggered an i64-vs-%T mismatch in let-stmt — leaving HTTP-stack
// code (ParsedHead, http_proxy buffered path) on the tagged-struct
// workaround.

$ `stdlib/core/string.nu`

// Multi-field struct, f0 is i (non-pointer) → heap-box payload.
: Pt2 {
    i x
    i y
}

// Mixed: f0 is %String (struct handle, NOT a pointer type). Same
// heap-box path because f0_ty doesn't end with '*'.
: Tagged {
    String label
    i count
}

| Err1 {
    Empty
    BadFormat
}

@ make_pt i x i y → !Pt2 Err1 {
    ? < x 0 { ^ @ !Pt2 Err1 { F Empty } } {}
    : Pt2 p @ Pt2 { x y }
    ^ @ !Pt2 Err1 { T p }
}

@ make_tagged s lbl i n → !Tagged Err1 {
    ? < n 0 { ^ @ !Tagged Err1 { F BadFormat } } {}
    : Tagged t @ Tagged { ( string_from lbl ) n }
    ^ @ !Tagged Err1 { T t }
}

// Caller chains `\` to unwrap a multi-field Ok payload, then forwards
// it as the Ok of an outer Result. Exercises both: the inner `\`
// (which must heap-unbox), and a follow-up construction that re-boxes.
@ shift_pt i x i y i dx i dy → !Pt2 Err1 {
    : Pt2 base \ ( make_pt x y )
    : Pt2 shifted @ Pt2 { + . base x dx + . base y dy }
    ^ @ !Pt2 Err1 { T shifted }
}

@ tag_len s lbl i n → !Tagged Err1 {
    : Tagged t \ ( make_tagged lbl n )
    ^ @ !Tagged Err1 { T t }
}

@ main → i {
    // ── Pt2 chain ─────────────────────────────────────────────────
    : !Pt2 Err1 r1 ( shift_pt 3 4 10 20 )
    ?? r1 {
        T p → {
            : Pt2 pp # Pt2 p
            ( nurl_print `pt: ` )
            ( nurl_print ( nurl_str_int . pp x ) )
            ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int . pp y ) )
            ( nurl_print `\n` )
        }
        F e → ( nurl_print `pt: err\n` )
    }

    // Failure short-circuit — \ in shift_pt should propagate the Err arm
    : !Pt2 Err1 r2 ( shift_pt - 0 1 0 99 99 )
    ?? r2 {
        T p → ( nurl_print `pt-neg: ok\n` )
        F e → ( nurl_print `pt-neg: propagated\n` )
    }

    // ── Tagged (f0 = %String struct handle, NOT pointer) ───────────
    : !Tagged Err1 r3 ( tag_len `hello` 7 )
    ?? r3 {
        T t → {
            : Tagged tt # Tagged t
            ( nurl_print `tag: ` )
            ( nurl_print ( string_data . tt label ) )
            ( nurl_print `/` )
            ( nurl_print ( nurl_str_int . tt count ) )
            ( nurl_print `\n` )
            ( string_free . tt label )
        }
        F e → ( nurl_print `tag: err\n` )
    }

    ^ 0
}
