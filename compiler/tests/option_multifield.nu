// Test: `? T` where T is a multi-field struct. Mirrors result_multifield.nu
// for the Option case. Previously `vec_get [MultiFieldStruct]` and other
// stdlib `@ ? T { F # T 0 }` dummy-payload idioms miscompiled when T's
// first field was a struct (e.g. %String inside Header) — the i64 0
// landed in a non-i64 slot and produced invalid LLVM IR
// (`insertvalue %Header undef, i64 0, 0` rejected as type mismatch).
//
// Fix: gen_cast's i64→struct branch now emits zeroinitializer when f0
// is neither a pointer nor i64, servicing the standard None-payload
// idiom across vec_get / hashmap / iter combinators (a multi-field
// option-payload codegen case).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// 2-field struct (int + int): f0 is i64 — already worked, regression guard.
: Pt2 {
    i x
    i y
}

// 4-field struct: wider non-pointer-f0 case.
: Quad {
    i a
    i b
    i c
    i d
}

// 2-field struct with %String first (struct, not pointer):
// THE failing case before the fix.
: Tagged {
    String label
    i count
}

@ make_pt i x i y → ?Pt2 {
    ? < x 0 { ^ @ ?Pt2 { F } } {}
    : Pt2 p @ Pt2 { x y }
    ^ @ ?Pt2 { T p }
}

@ make_quad → ?Quad {
    : Quad q @ Quad { 7 11 13 17 }
    ^ @ ?Quad { T q }
}

@ make_tagged s lbl i n → ?Tagged {
    ? < n 0 { ^ @ ?Tagged { F } } {}
    : Tagged t @ Tagged { ( string_from lbl ) n }
    ^ @ ?Tagged { T t }
}

@ main → i {
    // ── Pt2 (i, i) ─────────────────────────────────────────────────
    : ?Pt2 r1 ( make_pt 3 4 )
    ?? r1 {
        T p → {
            : Pt2 pp # Pt2 p
            ( nurl_print `pt: x=` )
            ( nurl_print ( nurl_str_int . pp x ) )
            ( nurl_print ` y=` )
            ( nurl_print ( nurl_str_int . pp y ) )
            ( nurl_print `\n` )
        }
        F → ( nurl_print `pt: none\n` )
    }

    // None path
    : ?Pt2 r2 ( make_pt - 0 5 1 )
    ?? r2 {
        T p → ( nurl_print `pt-neg: ok?!\n` )
        F → ( nurl_print `pt-neg: none\n` )
    }

    // ── Quad (4 fields) ────────────────────────────────────────────
    : ?Quad r3 ( make_quad )
    ?? r3 {
        T q → {
            : Quad qq # Quad q
            ( nurl_print `quad: ` )
            ( nurl_print ( nurl_str_int . qq a ) ) ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int . qq b ) ) ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int . qq c ) ) ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int . qq d ) ) ( nurl_print `\n` )
        }
        F → ( nurl_print `quad: none\n` )
    }

    // ── Tagged (String, i) — f0 is a STRUCT (%String). ────────────
    : ?Tagged r4 ( make_tagged `hello` 42 )
    ?? r4 {
        T t → {
            : Tagged tt # Tagged t
            ( nurl_print `tagged: ` )
            ( nurl_print ( string_data . tt label ) )
            ( nurl_print ` count=` )
            ( nurl_print ( nurl_str_int . tt count ) )
            ( nurl_print `\n` )
            ( string_free . tt label )
        }
        F → ( nurl_print `tagged: none\n` )
    }

    // ── vec_get [Tagged] — exercises the `@ ? A { F # A 0 }` None
    //    idiom on a multi-field T with %String f0. THIS is the line
    //    that miscompiled before the gen_cast fix.
    : ( Vec Tagged ) ts ( vec_new [Tagged] )
    ( vec_push [Tagged] ts ( make_tagged_raw `first` 1 ) )
    ( vec_push [Tagged] ts ( make_tagged_raw `second` 2 ) )

    // In-range
    : ?Tagged g1 ( vec_get [Tagged] ts 1 )
    ?? g1 {
        T t → {
            : Tagged tt # Tagged t
            ( nurl_print `vget[1]: ` )
            ( nurl_print ( string_data . tt label ) )
            ( nurl_print `/` )
            ( nurl_print ( nurl_str_int . tt count ) )
            ( nurl_print `\n` )
        }
        F → ( nurl_print `vget[1]: none?!\n` )
    }

    // Out-of-bounds — None via `@ ? Tagged { F # Tagged 0 }`
    : ?Tagged g2 ( vec_get [Tagged] ts 99 )
    ?? g2 {
        T t → ( nurl_print `vget[99]: some?!\n` )
        F → ( nurl_print `vget[99]: none\n` )
    }

    // Cleanup owned %String fields inside the Vec.
    : i n ( vec_len [Tagged] ts )
    : *Tagged tdata ( vec_data [Tagged] ts )
    : ~ i k 0
    ~ < k n {
        ( string_free . . tdata k label )
        = k + k 1
    }
    ( vec_free [Tagged] ts )

    ^ 0
}

// Helper that doesn't fail — keeps the Vec push expression simple.
@ make_tagged_raw s lbl i n → Tagged {
    ^ @ Tagged { ( string_from lbl ) n }
}
