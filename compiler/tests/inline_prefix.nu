// inline_prefix.nu — the `inline` always-inline prefix (grammar v2.7).
//
// The prefix puts LLVM's `alwaysinline` on the definition. Nothing about
// the program's MEANING changes, which is the point: this test proves the
// prefix parses in every accepted position, composes with `pub` in either
// order, and leaves the values a marked function computes identical to an
// unmarked twin's.
//
// The rejections (`inline` on a generic, on a non-`@` declaration, together
// with `simd`, or as a binding name) are covered by should_fail_inline_*.

@ plain i a i b → i { ^ + * a b 3 }

inline @ marked i a i b → i { ^ + * a b 3 }

pub inline @ pub_first i x → i { ^ * x 10 }

inline pub @ inline_first i x → i { ^ + x 7 }

// Directly recursive, and marked: LLVM inlines the call sites it can and
// leaves the self-call alone. Accepted rather than diagnosed, because the
// backend's answer is well-defined.
inline @ fact i n → i {
    ? <= n 1 { ^ 1 } {}
    ^ * n ( fact - n 1 )
}

// A marked helper whose arguments are constants at the call site — the
// shape the prefix exists for: inlined, the body folds to nothing.
inline @ lane i v i k → i { ^ & ( __lshr64_t v * k 8 ) 255 }

@ __lshr64_t i x i n → i { ^ & >> x n ( __mask_t n ) }

@ __mask_t i n → i { ? == n 0 { ^ -1 } {} ^ - << 1 - 64 n 1 }

@ show s label i got i want → v {
    ( nurl_print label )
    ( nurl_println_int got )
    ( nurl_print ? == got want ` ok\n` ` MISMATCH\n` )
}

@ main → i {
    ( show `plain 4 5:        ` ( plain 4 5 ) 23 )
    ( show `marked 4 5:       ` ( marked 4 5 ) 23 )
    ( show `pub_first 6:      ` ( pub_first 6 ) 60 )
    ( show `inline_first 6:   ` ( inline_first 6 ) 13 )
    ( show `fact 10:          ` ( fact 10 ) 3628800 )
    ( show `lane 0x0102 byte1:` ( lane 258 1 ) 1 )
    ( show `lane 0x0102 byte0:` ( lane 258 0 ) 2 )
    ^ 0
}
