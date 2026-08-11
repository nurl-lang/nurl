// diag_bind_int_to_ptr.nu — initialising a pointer binding from a bare
// integer. `: *i p 0` used to emit `store i64* 0` (an integer constant
// of pointer type — invalid IR that nurlc accepted, rc 0, and only
// clang rejected). The spec'd "null idiom" this spelling suggested
// never linked; the honest null pointer is the explicit '# *T 0' cast,
// and the diagnostic says so.
@ main → i {
    : *i p 0
    ^ 0
}
