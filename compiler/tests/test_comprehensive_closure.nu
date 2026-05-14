// test_comprehensive_closure.nu
// Comprehensive test for parameter parsing

@ main → i {
    // Zero parameters
    : ( @ i ) zero \ → i { ^ 42 }

    // Single parameter
    : ( @ i i ) square \ i x → i { * x x }

    // Different types
    : ( @ f f ) double \ f x → f { + x x }
    : ( @ b b ) negate \ b x → b { ! x }

    ( nurl_print `All closures compiled successfully!\n` )
    ^ 0
}
