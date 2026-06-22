// should_fail_return_type_mismatch.nu — returning a value whose type clashes
// with the declared return type (`^ `hi`` from a `→ i` function). gen_ret now
// rejects the never-valid float/non-float and pointer/non-pointer cases.
@ f → i { ^ `hi` }

@ main → i { ^ ( f ) }
