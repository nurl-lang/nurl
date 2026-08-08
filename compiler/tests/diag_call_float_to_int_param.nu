// diag_call_float_to_int_param.nu — a float argument handed to an
// integer parameter must be a compile error (spec §4.1: no implicit
// conversions). It used to emit `call i64 @twice(double …)` — textually
// valid IR under opaque pointers (the call carries its own function
// type), so clang assembled it and the callee read an unrelated
// register at runtime: silent garbage, not even a crash. Found live via
// the playground MCP (t4_type.nu, 2026-08-08).
@ twice i x → i { ^ * 2 x }

@ main → i {
    : f y 1.5
    : i z ( twice y )
    ^ z
}
