// diag_inout_arg_not_in_scope.nu — an inout argument naming nothing.
@ bump inout i x → v { = x + x 1 }

@ main → i {
    ( bump zzz )
    ^ 0
}
