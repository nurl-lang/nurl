// diag_bind_unknown_ptr_type.nu — a binding whose type names a struct
// that was never declared.
//
// check_type_known already guarded parameter, struct-field, return and
// FFI types; the binding — the place a type is written most often — was
// the one position it never covered, so '%Foo' leaked into the IR and
// only clang objected, far from the source.
@ main → i {
    : *Foo p ( nurl_alloc 8 )
    ^ 0
}
