// diag_call_ffi_float_to_int.nu — the FFI coercion block handled
// integer widths and pointer↔int, but a float argument against a C
// integer parameter slid through as `call i64 @labs(double …)`: the
// x86-64 ABI puts the double in xmm0 while labs reads rdi — garbage in,
// garbage out, no diagnostic anywhere.
& `c` @ labs i n → i

@ main → i {
    : f y 1.5
    ^ ( labs y )
}
