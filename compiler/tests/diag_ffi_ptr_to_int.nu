// diag_ffi_ptr_to_int.nu — a pointer passed to an FFI parameter
// declared as an integer. This was a silent ptrtoint: the callee read
// the string's ADDRESS as its number — the same silent-garbage class
// as `call i64 @f(double …)`. The honest spelling for the rare
// intended case (uintptr_t) is the explicit '# i x' conversion, so
// the implicit bridge is now a diagnostic. (The reverse direction —
// an integer into a pointer parameter — stays legal: '( free 0 )' is
// the NULL idiom, and a handle held as i64 crosses the same way.)

& `c` @ labs i x → i

@ main → i {
    : i r ( labs `hello` )
    ( nurl_print_int r )
    ^ 0
}
