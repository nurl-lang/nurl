// diag_inout_field_on_scalar.nu — an inout field target whose object is
// a scalar, so it has no declared field names to reach for.
@ bump inout i x → v { = x + x 1 }

@ main → i {
    : ~ i n 5
    ( bump . n a )
    ^ n
}
