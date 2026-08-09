// diag_ffi_arity_few.nu — an FFI call with fewer arguments than the
// declaration: the sharper dual. `( pow 2.0 )` assembled AND ran — the
// callee read an unset ABI register for y, silently.
& `m` @ pow f x f y → f

@ main → i {
    : f z ( pow 2.0 )
    ^ 0
}
