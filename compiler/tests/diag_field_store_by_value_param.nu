// diag_field_store_by_value_param.nu — assigning to a field of a
// by-value struct parameter.
//
// This was a silent invalid-IR bug, not a missing message. A by-value
// struct parameter has no alloca to GEP from, so the store emitted
//
//     %r1 = getelementptr %S, %S* , i32 0, i32 0
//
// with an EMPTY pointer operand. nurlc printed it with status 0 and
// only clang objected, as "expected value token" against generated IR
// the author never wrote.
: S { i a }

@ f S s → i {
    = . s a 5
    ^ . s a
}

@ main → i {
    : S s @ S { 1 }
    ^ ( f s )
}
