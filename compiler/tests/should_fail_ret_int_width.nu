// Returning an `i` from a `→ b` function (or a `b` from `→ i`) used to
// emit `ret i64 …` out of an i1 LLVM function — invalid IR nurlc
// accepted (rc 0) and only the LLVM verifier rejected, three build
// stages later. The classic trigger: tail-returning an int-returning
// FFI call from a bool-typed wrapper. Must be a compile error with the
// cure ('^ != 0 ( … )') in the message.
$ `stdlib/core/string.nu`

@ streq s a s b → b { ^ ( nurl_str_eq a b ) }

@ main → i {
    ? ( streq `x` `x` ) { ^ 0 } {}
    ^ 1
}
