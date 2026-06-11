// Regression: a `??`-match on a result/option-typed PARAMETER must
// reconstruct a struct / pointer / unsigned payload in the T-arm — the
// same way a let-bound result var does.
//
// The bug: gen_fn_param parsed a parameter's `! T E` / `? T` type but
// never recorded the `<param>__res_nurl_T` / `__res_t_llvm` /
// `__opt_nurl_T` metadata that gen_let_or_struct records for let-bound
// result vars. So `@ f !S E r → S { ?? r { T x → ^ x } }` left `x` as
// the raw i64 payload slot and emitted `ret i64` against the `%S`
// return type — an LLVM "value doesn't match function result type"
// error. The same gap mishandled a `( Vec u )` handle payload and
// dropped the unsigned flag on a `?u` parameter (sign-extending a byte
// ≥ 0x80). Fix: gen_fn_param now mirrors gen_let_or_struct's metadata
// recording for result/option parameters.
//
// Each printed line is deterministic so the output is baselined.

$ `stdlib/core/vec.nu`

: S { s name }
: | E { Ea Eb }

// (1) single-pointer-handle struct payload, returned straight from a
// result PARAMETER's T-arm.
@ unwrap_struct !S E r → S {
    ?? r { T x → ^ x  F e → ^ @ S { `?` } }
}

// (2) `( Vec u )` handle payload from a result PARAMETER.
@ unwrap_vec ! ( Vec u ) E r → ( Vec u ) {
    ?? r { T x → ^ x  F e → ^ ( vec_new [u] ) }
}

// (3) unsigned-byte payload from an option PARAMETER — must zext, not
// sext (0x86 = 134, not -122).
@ unwrap_opt_u ?u o → i {
    ?? o { T b → ^ # i b  F _ → ^ -1 }
}

@ main → i {
    : S s1 ( unwrap_struct @ !S E { T @ S { `hello` } } )
    ( nurl_print `struct=` ) ( nurl_print . s1 name ) ( nurl_print `\n` )

    : ( Vec u ) v ( vec_with_cap [u] 3 )
    ( vec_push [u] v # u 0x86 )
    ( vec_push [u] v # u 2 )
    : ( Vec u ) v2 ( unwrap_vec @ ! ( Vec u ) E { T v } )
    ( nurl_print `veclen=` ) ( nurl_print ( nurl_str_int ( vec_len [u] v2 ) ) ) ( nurl_print `\n` )

    ( nurl_print `optu=` ) ( nurl_print ( nurl_str_int ( unwrap_opt_u @ ?u { T 0x86 } ) ) ) ( nurl_print `\n` )
    ( nurl_print `optn=` ) ( nurl_print ( nurl_str_int ( unwrap_opt_u @ ?u { F # u 0 } ) ) ) ( nurl_print `\n` )
    ^ 0
}
