// diag_generic_body_error_loc.nu — an error inside a generic
// function's body must point at the template's REAL file and line.
// The template used to be captured as one flat line and re-lexed under
// a synthetic filename, so the diagnostic read
// '<generic scale2__i64 from file:N>:1:C: …' — unparseable (spaces in
// the "filename") and pointing at line 1 of a buffer nobody can open.
// Line-preserving capture + a padded re-lex buffer anchor it at the
// template's own line below; the instantiation context (mangled name,
// first call site) rides the message tail, because a mono error can
// depend on the concrete type arguments.

@ scale2 [T] T x → T {
    : T doubled + x x
    ^ * doubled missing_factor
}

@ main → i {
    ^ ( scale2 [i] 21 )
}
