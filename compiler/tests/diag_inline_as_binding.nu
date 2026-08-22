// diag_inline_as_binding.nu — `inline` is a reserved word (grammar v2.7).
//
// It lexes as TT_INLINE everywhere, not only before a declaration, so
// using it as a binding name is a diagnostic that names the reason rather
// than a parse error one token later.

@ main → i {
    : i inline 3
    ^ inline
}
