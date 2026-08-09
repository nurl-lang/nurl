// diag_ffi_arity_many.nu — an FFI call with more arguments than the
// declaration. Under opaque pointers the emitted call carries its own
// signature, so `( sin 1.0 2.0 )` against a one-param declaration
// ASSEMBLED and ran — the surplus silently ignored.
& `m` @ sin f x → f

@ main → i {
    : f z ( sin 1.0 2.0 )
    ^ 0
}
