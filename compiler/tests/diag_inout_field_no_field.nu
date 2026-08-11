// diag_inout_field_no_field.nu — an inout field target with the object
// named and the field left off.
: S { i a }

@ bump inout i x → v { = x + x 1 }

@ main → i {
    : ~ S s @ S { 1 }
    ( bump . s )
    ^ 0
}
