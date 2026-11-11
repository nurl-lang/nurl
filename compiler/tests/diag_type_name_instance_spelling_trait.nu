// diag_type_name_instance_spelling_trait.nu — a trait's name holds no `__`
// past its leading underscores, as a struct's does not
// (diag_type_name_instance_spelling_struct.nu): a trait object's type is
// spelled by the trait's name, and the rules read that name up to the
// first `__`.

% Arc__Maker [T] {
    @ make T self → i
}

: Bag { i n }

% Arc__Maker Bag {
    @ make Bag self → i { ^ . self n }
}

@ main → i {
    : Bag bag @ Bag { 3 }
    ^ - ( make bag ) 3
}
