// generic_signedness_mono.nu — a generic body's signed-sensitive operators
// (/ % >> and comparisons) must use the signedness of the CONCRETE type
// argument, not whichever instantiation was emitted first.
//
// Regression for a silent miscompile: `mangle_type` keys on the LLVM type,
// where `i` and `u64` (also `u`/i8, `u16`/i16, `u32`/i32) both lower to the
// same width. So `( gdiv [u64] )` and `( gdiv [i] )` collapsed onto ONE
// monomorph; the u64 one (encountered first) used `udiv`, so `gdiv [i] -7 2`
// computed udiv(-7,2) = 9223372036854775804 instead of -3. mangle_src_word now
// gives unsigned leaves distinct slugs so the monomorphs stay separate.
@ gdiv [T] T a T b → T { ^ / a b }

@ gmod [T] T a T b → T { ^ % a b }

@ gshr [T] T a → T { ^ >> a 1 }

@ main → i {
    // Instantiate the UNSIGNED monomorphs FIRST so a regression would poison
    // the signed bodies below.
    ( nurl_print ( nurl_str_int # i ( gdiv [u64] 200 100 ) ) ) ( nurl_print `\n` )  // 2
    ( nurl_print ( nurl_str_int # i ( gmod [u64] 200 100 ) ) ) ( nurl_print `\n` )  // 0
    ( nurl_print ( nurl_str_int # i ( gshr [u64] 64 ) ) ) ( nurl_print `\n` )  // 32

    // Signed bodies: must use sdiv / srem / ashr regardless of emit order.
    ( nurl_print ( nurl_str_int ( gdiv [i] -7 2 ) ) ) ( nurl_print `\n` )  // -3
    ( nurl_print ( nurl_str_int ( gmod [i] -7 2 ) ) ) ( nurl_print `\n` )  // -1
    ( nurl_print ( nurl_str_int ( gshr [i] -8 ) ) ) ( nurl_print `\n` )  // -4
    ^ 0
}
