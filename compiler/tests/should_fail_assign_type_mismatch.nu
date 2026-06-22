// should_fail_assign_type_mismatch.nu — assigning a float to an int binding
// (`= n 1.5`). Same store-clash guard as the let path.
@ main → i { : ~ i n 0 = n 1.5 ^ 0 }
