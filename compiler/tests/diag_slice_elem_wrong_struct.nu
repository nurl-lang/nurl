// diag_slice_elem_wrong_struct.nu — a value of one named struct type in
// a slice literal declared for another.
: A { i x }
: B { i y }

@ main → i {
    : A a @ A { 1 }
    : B b @ B { 2 }
    : [A xs [A | a b]
    ^ 0
}
