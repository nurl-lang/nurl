// diag_struct_lit_ptr_field.nu — a pointer value supplied for a
// scalar struct-literal field. The float and named-struct clashes were
// already rejected; the pointer one still emitted `insertvalue %P …,
// i8* …` into an i64 slot — invalid IR only clang reported. The reverse
// direction (an integer into a pointer-typed field) stays legal: it is
// the '@ P { 0 }' null idiom and the handle-stash coercion.
: P { i x i y }

@ main → i {
    : P p @ P { `hi` 2 }
    ^ . p y
}
