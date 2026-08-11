// diag_assign_immutable_scalar_param.nu — assigning to a scalar
// parameter. The struct-field sibling of this lives in
// diag_field_store_by_value_param; this is the plain path.
@ f i p → i {
    = p 5
    ^ p
}

@ main → i { ^ ( f 1 ) }
