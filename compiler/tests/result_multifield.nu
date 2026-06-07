// Test: `! T E` where T is a multi-field struct.
//
// The compiler heap-boxes multi-field T transparently: alloc + store
// + ptrtoint into the i64 payload slot at construction; the matching
// `??` arm inttoptr + load + free at destructure.

$ `stdlib/core/string.nu`

// 2-field struct (int + int): f0 is i64 (not pointer).
: Pt2 {
    i x
    i y
}

// 4-field struct (int + int + int + int): wider non-pointer-f0 case.
: Quad {
    i a
    i b
    i c
    i d
}

// 2-field struct mixing String and int. f0 is %String (a struct, not a
// pointer): the caller's match arm must reconstruct the whole struct
// not just f0.
: Tagged {
    String label
    i count
}

// Self-contained error enum. Uses unique variant names so it doesn't
// collide with the ParseErr (Empty/BadFormat) that string.nu pulls in
// transitively via errors.nu. (This was written `| ParseErr` with a
// bare `|`, which the front-end used to silently skip — now a hard
// error; the canonical spelling is `: |`.)
: | MfErr {
    MfEmpty
    MfBad
}

@ make_pt i x i y → !Pt2 MfErr {
    ? < x 0 { ^ @ !Pt2 MfErr { F MfEmpty } } {}
    : Pt2 p @ Pt2 { x y }
    ^ @ !Pt2 MfErr { T p }
}

@ make_quad → !Quad MfErr {
    : Quad q @ Quad { 7 11 13 17 }
    ^ @ !Quad MfErr { T q }
}

@ make_tagged s lbl i n → !Tagged MfErr {
    ? < n 0 { ^ @ !Tagged MfErr { F MfBad } } {}
    : Tagged t @ Tagged { ( string_from lbl ) n }
    ^ @ !Tagged MfErr { T t }
}

@ main → i {
    // ── Pt2 (i, i) ─────────────────────────────────────────────────
    : !Pt2 MfErr r1 ( make_pt 3 4 )
    ?? r1 {
        T p → {
            : Pt2 pp # Pt2 p
            : i px . pp x
            : i py . pp y
            ( nurl_print `pt: x=` )
            ( nurl_print ( nurl_str_int px ) )
            ( nurl_print ` y=` )
            ( nurl_print ( nurl_str_int py ) )
            ( nurl_print `\n` )
        }
        F e → ( nurl_print `pt: err\n` )
    }

    // Error path: should NOT trigger heap-box load (different variant).
    : !Pt2 MfErr r2 ( make_pt - 0 5 1 )
    ?? r2 {
        T p → ( nurl_print `pt-neg: ok\n` )
        F e → ( nurl_print `pt-neg: err\n` )
    }

    // ── Quad (4 fields) ────────────────────────────────────────────
    : !Quad MfErr r3 ( make_quad )
    ?? r3 {
        T q → {
            : Quad qq # Quad q
            : i qa . qq a
            : i qb . qq b
            : i qc . qq c
            : i qd . qq d
            ( nurl_print `quad: ` )
            ( nurl_print ( nurl_str_int qa ) ) ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int qb ) ) ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int qc ) ) ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int qd ) ) ( nurl_print `\n` )
        }
        F e → ( nurl_print `quad: err\n` )
    }

    // ── Tagged (String, i) — f0 is a STRUCT (%String). ────────────
    : !Tagged MfErr r4 ( make_tagged `hello` 42 )
    ?? r4 {
        T t → {
            : Tagged tt # Tagged t
            : String lbl . tt label
            : i tcnt . tt count
            ( nurl_print `tagged: ` )
            ( nurl_print ( string_data lbl ) )
            ( nurl_print ` count=` )
            ( nurl_print ( nurl_str_int tcnt ) )
            ( nurl_print `\n` )
            ( string_free lbl )
        }
        F e → ( nurl_print `tagged: err\n` )
    }

    ^ 0
}
