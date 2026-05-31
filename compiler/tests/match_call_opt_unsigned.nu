// Regression: matching a `? u` option whose scrutinee is a DIRECT CALL
// must propagate the inner type's unsigned-ness to the bound payload, so
// a later `# i b` widen zero-extends (0x86 → 134) instead of sign-
// extending (0x86 → -122).
//
// The bug (project memory `nurl_lang_gotchas`): the option-inner NURL
// type was stashed as `<name>__opt_nurl_T` only for a NAMED-binding
// scrutinee (gen_let_or_struct, from the binding's declared `? u` type).
// A direct-call scrutinee `?? ( vec_get [u] v 0 ) { T b → … }` had no
// binding, so gen_match's T-arm payload skipped the unsigned tag and the
// widen sign-extended — silent wrong value for every byte ≥ 0x80. This
// is the option analogue of the `! T E` bound-`??` direct-call gap.
//
// Fix: the callee's option-inner NURL token is recorded per-function as
// `<fname>__opt_nurl_t` (eagerly under the mangled name for generics, via
// compute_generic_ret_ty's substituted parse), surfaced to gen_call as
// `__last_call_opt_nurl_t__`, and gen_match's direct-call synthesis sets
// `<msynth>__opt_nurl_T` from it so the existing T-arm consultation fires.
//
// Covers: unsigned (zero-extend), signed (preserved), and two generic
// instantiations interleaved in one scope (stale-metadata guard).

$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec u ) vu ( vec_new [u] )
    ( vec_push [u] vu 0x86 )
    ( vec_push [u] vu 0x7f )

    // unsigned high-bit byte via direct-call match → zero-extend.
    ?? ( vec_get [u] vu 0 ) { T b → ( nurl_print ( nurl_str_int # i b ) ) F → ( nurl_print `none` ) }
    ( nurl_print ` ` )
    // unsigned low-bit byte → unchanged either way, sanity.
    ?? ( vec_get [u] vu 1 ) { T b → ( nurl_print ( nurl_str_int # i b ) ) F → ( nurl_print `none` ) }
    ( nurl_print `\n` )

    // signed vec: a negative value must stay negative.
    : ( Vec i ) vi ( vec_new [i] )
    ( vec_push [i] vi -5 )
    ?? ( vec_get [i] vi 0 ) { T b → ( nurl_print ( nurl_str_int b ) ) F → ( nurl_print `none` ) }
    ( nurl_print `\n` )

    // interleaved u / i instantiations in one scope — the second u read
    // must not inherit stale option-inner metadata from the i read.
    ?? ( vec_get [i] vi 0 ) { T b → ( nurl_print ( nurl_str_int b ) ) F → ( nurl_print `none` ) }
    ( nurl_print ` ` )
    ?? ( vec_get [u] vu 0 ) { T b → ( nurl_print ( nurl_str_int # i b ) ) F → ( nurl_print `none` ) }
    ( nurl_print `\n` )
    ^ 0
}
