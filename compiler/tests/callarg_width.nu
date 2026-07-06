// callarg_width.nu — lock for call-argument integer-width coercion.
//
// A sized-int parameter (`u`, `u16`, `i32`, …) called with an i64 value
// (any bare literal, or a plain `i` variable) must trunc/extend at the
// call site so the call's argument types match the definition. The
// native ABI masked the mismatch (callee reads the low register bytes);
// on wasm32 the signature mismatch made wasm-ld emit a trapping
// `.L*_bitcast_invalid` stub — yoloe-in-the-browser died in image_new's
// `( vec_push [u] d 0 )`. Generic calls substitute the call's type args
// into the declared tparam sources first.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`

@ take8 u x → i { ^ # i x }

@ take16 u16 x → i { ^ # i x }

@ take32 i32 x → i { ^ # i x }

@ gpush [A] ( Vec A ) v A x → v { ( vec_push [A] v x ) }

@ main → i {
    // non-generic: literals + a runtime i64
    ( nurl_print ( nurl_str_int ( take8 7 ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( take8 300 ) ) ) ( nurl_print `\n` )  // trunc: 300 → 44
    ( nurl_print ( nurl_str_int ( take16 70000 ) ) ) ( nurl_print `\n` )  // trunc: 70000 → 4464
    ( nurl_print ( nurl_str_int ( take32 7 ) ) ) ( nurl_print `\n` )
    : i big 200
    ( nurl_print ( nurl_str_int ( take8 big ) ) ) ( nurl_print `\n` )

    // generic monomorph: literal through [u] instantiation
    : ( Vec u ) d ( vec_with_cap [u] 4 )
    ( vec_push [u] d 0 )
    ( vec_push [u] d 200 )
    ( gpush [u] d 65 )
    ( nurl_print ( nurl_str_int ( vec_len [u] d ) ) ) ( nurl_print `\n` )
    : i s0 ?? ( vec_get [u] d 1 ) { T x → # i x F _ → - 0 1 }
    ( nurl_print ( nurl_str_int s0 ) ) ( nurl_print `\n` )
    : i s1 ?? ( vec_get [u] d 2 ) { T x → # i x F _ → - 0 1 }
    ( nurl_print ( nurl_str_int s1 ) ) ( nurl_print `\n` )
    ^ 0
}
