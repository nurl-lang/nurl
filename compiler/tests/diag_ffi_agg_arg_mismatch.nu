// diag_ffi_agg_arg_mismatch.nu — an option passed to an FFI parameter
// declared as a scalar. No coercion branch claimed the pair (scalar
// agreement handles numbers, the inttoptr bridge handles integers into
// pointers), so the call was emitted as `call i64 @labs({ i1, i64 } %v)`
// — textually valid under opaque pointers, assembled by clang, and the
// callee read whichever bytes the ABI happened to put in the register.
// The FFI total-agreement backstop now rejects everything that does not
// end up matching the `declare`.

& `c` @ labs i x → i

@ main → i {
    : ?i o @ ?i { T 5 }
    : i r ( labs o )
    ( nurl_print_int r )
    ^ 0
}
