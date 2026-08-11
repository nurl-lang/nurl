// diag_inout_field_not_binding.nu — an inout field target whose object
// is not in scope at all.
: S { i a }

@ bump inout i x → v { = x + x 1 }

@ main → i {
    ( bump . zz a )
    ^ 0
}
