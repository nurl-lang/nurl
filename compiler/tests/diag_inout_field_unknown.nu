// diag_inout_field_unknown.nu — an inout field target naming a field the
// struct does not have. The message used to end mid-quote ("has no field
// 'zz") because its nurl_str_cat4 had no room left for the closing one.
: S { i a }

@ bump inout i x → v { = x + x 1 }

@ main → i {
    : ~ S s @ S { 1 }
    ( bump . s zz )
    ^ . s a
}
