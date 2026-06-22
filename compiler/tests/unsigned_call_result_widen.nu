// unsigned_call_result_widen.nu — `# i ( f … )` over a function whose return
// type is unsigned must ZERO-extend the i8/i16/i32 result, not sign-extend it.
//
// The LLVM return type can't carry signedness, so gen_call re-asserts the
// callee's `__ret_unsigned` flag onto `__last_unsigned__` after the call. For a
// GENERIC call the monomorph that records that flag is emitted later (deferred),
// so the call site derives the signedness from the substituted NURL return type
// (compute_generic_ret_src). Without this, `# i ( gmax [u32] 3000000000 1 )`
// sign-extended a value with the high bit set → -1294967296 instead of
// 3000000000.
@ gid [T] T x → T { ^ x }

@ gmax [T] T a T b → T { ^ ? > a b a b }

@ pass_u32 u32 x → u32 { ^ x }

@ main → i {
    // Unsigned generic results: zero-extend.
    ( nurl_print ( nurl_str_int # i ( gid [u32] 4000000000 ) ) ) ( nurl_print `\n` )  // 4000000000
    ( nurl_print ( nurl_str_int # i ( gid [u64] 200 ) ) ) ( nurl_print `\n` )  // 200
    ( nurl_print ( nurl_str_int # i ( gmax [u32] 3000000000 1 ) ) ) ( nurl_print `\n` )  // 3000000000
    // Signed generic result: sign-extend (unchanged).
    ( nurl_print ( nurl_str_int # i ( gid [i32] -5 ) ) ) ( nurl_print `\n` )  // -5
    // Non-generic unsigned result: zero-extend.
    ( nurl_print ( nurl_str_int # i ( pass_u32 4000000000 ) ) ) ( nurl_print `\n` )  // 4000000000
    ^ 0
}
