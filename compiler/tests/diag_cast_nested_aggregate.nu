// diag_cast_nested_aggregate.nu — casting a struct whose first field is
// itself a struct. '# i s' takes the first scalar, and there isn't one.
: Inner { i a i b }
: Outer { Inner i1 i c }

@ main → i {
    : Outer o @ Outer { @ Inner { 1 2 } 3 }
    : i n # i o
    ^ n
}
