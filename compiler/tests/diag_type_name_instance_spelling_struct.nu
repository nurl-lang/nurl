// diag_type_name_instance_spelling_struct.nu — a struct's name holds no
// `__` past its leading underscores. That spelling is the compiler's own:
// an instance of a generic type is named by it — `( Arc Bag )` is
// `Arc__Bag` — and the ownership and thread rules read a type's name up
// to the first `__` as the generic it was made from. A struct of the
// program's own spelled that way would be read as one (agora #639: as an
// Arc, whose changes through a by-value borrow are its own).

$ `stdlib/core/vec.nu`

: Arc__Bag { ( Vec i ) v }

@ main → i {
    : Arc__Bag bag @ Arc__Bag { ( vec_new [i] ) }
    ^ ( vec_len [i] . bag v )
}
