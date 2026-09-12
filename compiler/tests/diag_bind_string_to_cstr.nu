// diag_bind_string_to_cstr.nu — a `String` binding a raw C-string slot.
//
// `String` is a managed handle (a by-value `{ ptr }` struct); `s` is a
// bare `i8*`. Nothing converts between them implicitly — `string_data`
// takes one out, `string_from` puts one in — and the ARGUMENT path has
// said so for years ("String vs raw C-string mismatch"), as has the
// ASSIGNMENT path ("cannot assign a value of type '%String' to 'raw' of
// type 'i8*'"). The BINDING initialiser did not, because both sides are
// pointer-ish and every clause of its never-legal-mix test wanted one
// side not to be: the named-type clause requires NEITHER side to be a
// pointer, and `s` is one. So `: s raw t` emitted `store i8* %r4` with
// %r4 a `%String` — invalid IR only clang saw.
//
// It now calls the same __store_type_clash helper the assignment path
// does, which is what that path's own comment already claimed ("the
// store dual of the let-binding / call-arg checks"). Found by deleting
// the `#` from `: s raw # s ( malloc 8 )` in
// borrow_strict_raw_ptr_escape.nu, which left the `s` binding in scope
// standing where the cast had been.

$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `x` )
    : s raw t
    ( nurl_print raw )
    ^ 0
}
