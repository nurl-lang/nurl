// pub_trait_ffi_visibility.nu — positive lock test for the grammar-v2
// visibility contract's deliberately-unenforced surface (spec §3.3).
//
// The helper (pub_trait_ffi_vis_mod.nu) is in strict mode and exports
// only `vtf_anchor` + `VtfWidget`. Its trait `VtfShow`, the
// `VtfShow (VtfWidget)` impl method `vtf_show`, and the `abs` FFI are all
// UNMARKED. Per the documented contract these stay callable across files:
// trait dispatch is type-mangled and FFI symbols are linker globals, so
// name-based visibility does not apply to them. This pins that conscious
// decision so it can't silently regress into enforcement (which would
// break type-driven dispatch and every cross-file FFI binding).
//
// The complementary NEGATIVE cases — a private @-fn / struct / const /
// enum variant rejected across files — live in the should_fail_pub_*
// tests. Together they lock the full contract.

$ `compiler/tests/pub_trait_ffi_vis_mod.nu`

@ main → i {
    : VtfWidget w @ VtfWidget { 42 }
    // Non-pub trait method, resolved by type across the file boundary.
    ( nurl_print `trait_show=` ) ( nurl_print ( nurl_str_int ( vtf_show w ) ) ) ( nurl_print `\n` )
    // Non-pub FFI extern, callable across the file boundary.
    ( nurl_print `ffi_abs=` ) ( nurl_print ( nurl_str_int ( abs - 0 7 ) ) ) ( nurl_print `\n` )
    ^ 0
}
