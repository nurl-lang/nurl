// Regression: binding a `??`-match as an expression on a DIRECT CALL
// whose result payload is a single-pointer handle (`( Vec u )` → %Vec)
// or a bare pointer (`s` → i8*) must reconstruct the payload in the
// T-arm — not leave it as the raw i64 result slot.
//
// The bug (critic.md "bound-`??` miscompile for SOME result types"):
//   : ( Vec u ) x ?? ( call ) { T v → v  F e → … }
// gen_match's payload reconstruction + result phi were keyed on the
// scrutinee being a NAMED binding (`<name>__res_t_llvm`, set by
// gen_let_or_struct from the binding's declared `! T E` type). A
// direct-call scrutinee has no such binding, so:
//   * handle payloads (Vec/String/…) skipped the inttoptr+insertvalue
//     reconstruction → T-arm value was raw i64, type-mismatched the
//     other arms, so NO phi was emitted and the binding got `undef`
//     (silent garbage handle → crash/empty on use); and
//   * bare-pointer payloads (`s` → i8*) were never reconstructed in
//     EITHER form because the reconstruction only handled `%`-structs.
//
// Fix: the callee's Ok-payload LLVM type is recorded per-function as
// `<fname>__res_t_llvm` (mirroring `__nurl_ret`); gen_match's direct-
// call synthesis reads it via the `__last_call_res_t_llvm__` side-
// channel, and the reconstruction grew a bare-pointer (`i8*`) path.
//
// Each line is deterministic so the output is baselined.

$ `stdlib/core/vec.nu`
$ `stdlib/core/result.nu`

@ make_vec i n → ! ( Vec u ) s {
    ? < n 0 { ^ @ ! ( Vec u ) s { F `negative` } } {}
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v 10 )
    ( vec_push [u] v 20 )
    ( vec_push [u] v 30 )
    ^ @ ! ( Vec u ) s { T v }
}

@ make_str b base → ! s s {
    ? base { ^ @ ! s s { T `ok-payload` } } {}
    ^ @ ! s s { F `err-payload` }
}

@ main → i {
    // (1) handle payload, direct-call scrutinee, binding position — the bug.
    : ( Vec u ) got ?? ( make_vec 1 ) {
        T v → v
        F e → ( vec_new [u] )
    }
    ( nurl_print `vec_direct_ok=` ) ( nurl_print ( nurl_str_int ( vec_len [u] got ) ) ) ( nurl_print `\n` )

    // (2) handle payload, error arm.
    : ( Vec u ) bad ?? ( make_vec -1 ) {
        T v → v
        F e → ( vec_new [u] )
    }
    ( nurl_print `vec_direct_err=` ) ( nurl_print ( nurl_str_int ( vec_len [u] bad ) ) ) ( nurl_print `\n` )

    // (3) handle payload, named scrutinee (must still work — the documented cure).
    : ! ( Vec u ) s r ( make_vec 1 )
    : ( Vec u ) got2 ?? r {
        T v → v
        F e → ( vec_new [u] )
    }
    ( nurl_print `vec_named_ok=` ) ( nurl_print ( nurl_str_int ( vec_len [u] got2 ) ) ) ( nurl_print `\n` )

    // (4) bare-pointer payload, direct-call scrutinee.
    : s sd ?? ( make_str T ) { T v → v  F e → e }
    ( nurl_print `str_direct=` ) ( nurl_print sd ) ( nurl_print `\n` )

    // (5) bare-pointer payload, error arm.
    : s se ?? ( make_str F ) { T v → v  F e → e }
    ( nurl_print `str_direct_err=` ) ( nurl_print se ) ( nurl_print `\n` )

    // (6) bare-pointer payload, named scrutinee (was ALSO broken).
    : ! s s rs ( make_str T )
    : s sn ?? rs { T v → v  F e → e }
    ( nurl_print `str_named=` ) ( nurl_print sn ) ( nurl_print `\n` )
    ^ 0
}
