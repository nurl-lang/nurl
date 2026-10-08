// diag_field_int_to_ptr.nu — a bare integer as the value of a
// pointer-typed struct-literal field. `@ P { 0 }` with a `*i` field
// used to emit `insertvalue %P zeroinitializer, i64 0, 0` — invalid IR
// that nurlc accepted (rc 0) and only clang rejected, with a .ll line
// number and no source location. The `@ P { 0 }` "null idiom" the old
// carve-out protected never produced linkable IR; a null field value
// is written explicitly, '@ P { # *i 0 }'. (A struct with a raw-pointer
// field is built only in 'unsafe' code, so main is one: the subject here
// is the field's type check.)
: P { * i q }

unsafe @ main → i {
    : P a @ P { 0 }
    ^ 0
}
