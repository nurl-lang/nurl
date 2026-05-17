// nested_match_enum.nu — regression for gotcha #6.
//
// Was: nested `??` on a value bound from an `F` arm of `! T E` (where
// E is an enum) emitted `extractvalue i64 %tag, 0`, which LLVM rejects
// with "extractvalue operand must be aggregate type" — i64 isn't an
// aggregate. Cause: gen_match always extractvalue'd to recover the
// tag, but for a bare-i64 enum value the tag IS the value.
//
// Fix: gen_match now skips extractvalue when match_type is `i64` (the
// same path the `i1` short-circuit takes). Bare scalar tag flows
// through to the enum-constant comparison unchanged.
//
// This test exercises the pattern in three shapes:
//   1. Direct `?? enum_value` on an enum-typed binding.
//   2. Nested `?? e` inside `?? r { F e → ... }` (the originally-reported case).
//   3. The same nested pattern with a wildcard `_` arm covering "other".

: | Color { Red Green Blue }
: | DbErr { NotFound Conflict Timeout Other }

@ classify_db !i DbErr r → s {
    ^ ?? r {
        T n → `ok`
        F e → ?? e {
            NotFound → `not_found`
            Conflict → `conflict`
            _ → `other`
        }
    }
}

@ describe_color Color c → s {
    // Direct ?? on a bare enum value.
    ^ ?? c {
        Red → `red`
        Green → `green`
        Blue → `blue`
    }
}

@ main → i {
    // ── case 1: direct enum match ───────────────────────────────
    ( nurl_print `c1=` ) ( nurl_print ( describe_color Red ) ) ( nurl_print `\n` )
    ( nurl_print `c2=` ) ( nurl_print ( describe_color Green ) ) ( nurl_print `\n` )
    ( nurl_print `c3=` ) ( nurl_print ( describe_color Blue ) ) ( nurl_print `\n` )

    // ── case 2: nested match — every variant ────────────────────
    : !i DbErr ok @ !i DbErr { T 42 }
    ( nurl_print `db_ok=` ) ( nurl_print ( classify_db ok ) ) ( nurl_print `\n` )

    : !i DbErr nf @ !i DbErr { F NotFound }
    ( nurl_print `db_nf=` ) ( nurl_print ( classify_db nf ) ) ( nurl_print `\n` )

    : !i DbErr cf @ !i DbErr { F Conflict }
    ( nurl_print `db_cf=` ) ( nurl_print ( classify_db cf ) ) ( nurl_print `\n` )

    : !i DbErr to @ !i DbErr { F Timeout }
    ( nurl_print `db_to=` ) ( nurl_print ( classify_db to ) ) ( nurl_print `\n` )

    ^ 0
}
