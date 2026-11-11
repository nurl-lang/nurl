// diag_type_name_trailing_underscore_trait.nu — a trait's name does not end
// in `_`, as a struct's does not
// (diag_type_name_trailing_underscore_struct.nu): a trait object's type is
// spelled by the trait's name.

% Maker_ [T] {
    @ make T self → i
}

: Bag { i n }

% Maker_ Bag {
    @ make Bag self → i { ^ . self n }
}

@ main → i {
    : Bag bag @ Bag { 3 }
    ^ - ( make bag ) 3
}
