// should_fail_let_type_mismatch.nu — an annotated binding initialised from a
// value of an incompatible type (`: i x 1.5`). coerce_store_val now rejects
// the never-valid float/non-float and pointer/non-pointer store clashes.
@ main → i { : i x 1.5  ^ 0 }
