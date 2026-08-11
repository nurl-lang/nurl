// dead_code_after_return.nu — statements after a terminator compile
// into a fresh unreferenced block instead of riding LLVM's
// implicit-block-after-terminator quirk. The old scheme was valid only
// when the dead run happened to end in a '^': a trailing call or
// binding produced "expected instruction opcode" from the verifier.
// Covers the corpus idiom (cleanup + defensive '^' after an infinite
// loop) and the plain dead-call-after-return shape, both of which must
// compile, link, and run with the dead code truly dead.
//
// Expected output:
//   f=1
//   g=7

@ f → i {
    ^ 1
    ( nurl_print `never printed\n` )
}

@ g i limit → i {
    : ~ i i 0
    ~ T {
        ? >= i limit { ^ i } {}
        = i + i 1
    }
    ( nurl_print `never printed either\n` )
    ^ 0
}

@ main → i {
    ( nurl_print `f=` ) ( nurl_print ( nurl_str_int ( f ) ) ) ( nurl_print `\n` )
    ( nurl_print `g=` ) ( nurl_print ( nurl_str_int ( g 7 ) ) ) ( nurl_print `\n` )
    ^ 0
}
