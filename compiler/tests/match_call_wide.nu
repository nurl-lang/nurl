// Regression: `?? ( call )` matching directly on a call whose result is
// a wide `! T E` payload (a multi-field value struct) must reconstruct
// the payload, not hand back the raw heap-box pointer.
//
// The wide-payload reconstruction in gen_match was gated on the
// scrutinee being a named binding (`<name>__res_nurl_T` lookup), so a
// direct-call scrutinee skipped it and the `T`-arm binding received the
// box pointer reinterpreted as the struct — silent garbage fields.
// gen_match now synthesises the binding metadata from the call's NURL
// return type, so the direct form reconstructs identically to `?? r`.

: W { i a  i b  i c  i d  i e  i f  i g  i h }
: | WErr { Bad }

@ mk_w i base → !W WErr {
    ? < base 0 { ^ @ !W WErr { F @ WErr { Bad } } } {}
    ^ @ !W WErr { T @ W { base + base 1 + base 2 + base 3 + base 4 + base 5 + base 6 + base 7 } }
}

@ show_w s tag W w → v {
    ( nurl_print tag )
    ( nurl_print `: ` )
    ( nurl_print ( nurl_str_int . w a ) )
    ( nurl_print ` ` )
    ( nurl_print ( nurl_str_int . w d ) )
    ( nurl_print ` ` )
    ( nurl_print ( nurl_str_int . w h ) )
    ( nurl_print `\n` )
}

@ main → i {
    // Direct match on the call — the regression case.
    ?? ( mk_w 10 ) {
        T w → ( show_w `direct_ok` w )
        F e → ( nurl_print `direct_ok: ERR\n` )
    }
    // Direct match, error arm.
    ?? ( mk_w -1 ) {
        T w → ( show_w `direct_err` w )
        F e → ( nurl_print `direct_err: rejected\n` )
    }
    // Bound form must still work.
    : !W WErr r ( mk_w 100 )
    ?? r {
        T w → ( show_w `bound_ok ` w )
        F e → ( nurl_print `bound_ok: ERR\n` )
    }
    ^ 0
}
