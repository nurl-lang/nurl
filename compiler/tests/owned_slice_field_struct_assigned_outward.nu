// owned_slice_field_struct_assigned_outward.nu — a struct whose slice field
// it owns (the literal gave it a fresh slice), assigned to a binding that
// outlives it: `= out tmp` moves tmp's value into out, owner flag and all,
// so tmp's drop at its block's end releases nothing and out owns the slice
// until main ends (agora #848: a slice a struct owns by type is the
// struct's, released and moved with it). This was diag_owned_fields_alias,
// refused while such a field was only a view the struct's binding happened
// to free; the move made it safe (docs/MEMORY.md §2.13).
$ `stdlib/core/string.nu`

: Bag { [i items i tag }

@ main → i {
    : ~ Bag out @ Bag { [i | 0] 500 }
    ? > ( nurl_str_len `ab` ) 1 {
        : Bag tmp @ Bag { [i | 1 2 3] 201 }
        = out tmp
    } {}
    ( nurl_print_int . out tag ) ( nurl_print `\n` )
    ( nurl_print_int . . out items 1 ) ( nurl_print `\n` )
    ^ 0
}
