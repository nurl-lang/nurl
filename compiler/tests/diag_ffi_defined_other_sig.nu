// diag_ffi_defined_other_sig.nu — a NURL function named like an FFI symbol
// defines that symbol for the whole program (ffi_decl_shadowed.nu), so it
// must have the declared signature.
//
// A program's own `@ round i x i q → i` beside std/float.nu's `& `m` @ round
// f x → f` replaced libm's `round` everywhere: float_round's call reached it
// with a double in a float register. The first news was an arity error
// inside std/float.nu, pointing at innocent code.
$ `stdlib/std/float.nu`

@ round i x i q → i { ^ * / + x / q 2 q q }

@ main → i {
    ( nurl_println ( nurl_str_float ( float_round 2.6 ) ) )
    ^ 0
}
