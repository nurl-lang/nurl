// diag_forward_value_type.nu — a named type used BY VALUE before its
// declaration. The compiler emits the program in order, so the binding's
// alloca met an opaque struct: clang said "Cannot allocate unsized type
// %Later" with a .ll line number and no source location, and when the
// body also read a field the field pass said "type 'Later' has no field
// 'a'" — the struct's fields were not registered yet — pointing at the
// access, not at the cause. The declaration site now says which type to
// move. A pointer to a later type is fine and stays fine.

$ `stdlib/core/vec.nu`

@ use_it → i {
    : Later x ( make )
    : i v . x a
    ( vec_free [i] . x xs )
    ^ v
}

: Later {
    i a
    ( Vec i ) xs
}

@ make → Later { ^ @ Later { 7 ( vec_new [i] ) } }

@ main → i { ^ - ( use_it ) 7 }
