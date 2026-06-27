// Test: Result widening — `!T E` is `{ i1, T, E }`.
//
// A multi-field struct Ok payload now rides field 1 BY VALUE; the Err payload
// rides field 2 BY VALUE. Before the widening a multi-field Ok was heap-boxed
// (nurl_alloc) to fit the single i64 slot. This test proves the round-trip via
// both `??` matching and direct `. r 1` / `. r 2` field access; the companion
// check `result_wide_noalloc` asserts make_ok emits no nurl_alloc.
$ `stdlib/core/string.nu`

: | WideErr { Boom Bust }

: Multi {
    i a
    i b
    i c
}

@ make_ok i x → !Multi WideErr {
    ^ @ !Multi WideErr { T @ Multi { x * x 2 * x 3 } }
}

@ make_err → !Multi WideErr {
    ^ @ !Multi WideErr { F Bust }
}

@ describe WideErr e → s {
    ^ ?? e { Boom → `boom` Bust → `bust` _ → `?` }
}

@ main → i {
    : !Multi WideErr r1 ( make_ok 7 )
    ?? r1 {
        T m → {
            ( nurl_print `ok ` )
            ( nurl_print ( nurl_str_int . m a ) ) ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int . m b ) ) ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int . m c ) ) ( nurl_print `\n` )
        }
        F e → ( nurl_print `unexpected-err\n` )
    }

    // Direct by-value field access: Ok struct payload rides field 1 whole.
    : Multi mm . r1 1
    ( nurl_print `direct ` )
    ( nurl_print ( nurl_str_int . mm a ) ) ( nurl_print ` ` )
    ( nurl_print ( nurl_str_int . mm c ) ) ( nurl_print `\n` )

    : !Multi WideErr r2 ( make_err )
    ?? r2 {
        T m → ( nurl_print `unexpected-ok\n` )
        F e → { ( nurl_print `err ` ) ( nurl_print ( describe e ) ) ( nurl_print `\n` ) }
    }

    // Direct by-value access of the Err payload (field 2).
    : WideErr ee . r2 2
    ( nurl_print `err2 ` ) ( nurl_print ( describe ee ) ) ( nurl_print `\n` )
    ^ 0
}
