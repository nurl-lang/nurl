// Test: `\ ( fn → ? T )` try-propagate where T is a multi-field struct.
// Twin of option_multifield.nu which exercises construction + `??`
// destructure. The `\` operator on Option propagates None to the
// caller; the Some-arm extractvalue yields the multi-field payload
// directly (Option keeps the natural `{ i1, %T }` layout — unlike
// `! T E` which heap-boxes through an i64 slot).

$ `stdlib/core/string.nu`

: Pt2 {
    i x
    i y
}

: Tagged {
    String label
    i count
}

@ make_pt i x i y → ?Pt2 {
    ? < x 0 { ^ @ ?Pt2 { F } } {}
    : Pt2 p @ Pt2 { x y }
    ^ @ ?Pt2 { T p }
}

@ make_tagged s lbl i n → ?Tagged {
    ? < n 0 { ^ @ ?Tagged { F } } {}
    : Tagged t @ Tagged { ( string_from lbl ) n }
    ^ @ ?Tagged { T t }
}

// Caller chains `\` to unwrap a multi-field Some payload, then
// forwards it as the Some of an outer Option.
@ shift_pt i x i y i dx i dy → ?Pt2 {
    : Pt2 base \ ( make_pt x y )
    : Pt2 shifted @ Pt2 { + . base x dx + . base y dy }
    ^ @ ?Pt2 { T shifted }
}

@ tag_len s lbl i n → ?Tagged {
    : Tagged t \ ( make_tagged lbl n )
    ^ @ ?Tagged { T t }
}

@ main → i {
    // ── Pt2 chain ─────────────────────────────────────────────────
    : ?Pt2 r1 ( shift_pt 3 4 10 20 )
    ?? r1 {
        T p → {
            : Pt2 pp # Pt2 p
            ( nurl_print `pt: ` )
            ( nurl_print ( nurl_str_int . pp x ) )
            ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int . pp y ) )
            ( nurl_print `\n` )
        }
        F → ( nurl_print `pt: none\n` )
    }

    // Failure short-circuit — `\` in shift_pt should propagate the None arm.
    : ?Pt2 r2 ( shift_pt - 0 1 0 99 99 )
    ?? r2 {
        T p → ( nurl_print `pt-neg: some?!\n` )
        F → ( nurl_print `pt-neg: propagated\n` )
    }

    // ── Tagged (f0 = %String struct handle, NOT pointer) ───────────
    : ?Tagged r3 ( tag_len `hello` 7 )
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
        F → ( nurl_print `tag: none\n` )
    }

    ^ 0
}
