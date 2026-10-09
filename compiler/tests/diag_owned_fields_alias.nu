// diag_owned_fields_alias.nu — a struct whose slice field it owns (the
// literal gave it a fresh slice), copied to a binding that outlives it.
// `tmp`'s field is freed when `tmp`'s block ends; `out` would still point
// at it (this program read freed memory before the rule). The fix: an
// owning field type (a Vec), so the value moves, or build the struct where
// it is kept. (A raw string field cannot own a fresh string in safe code
// at all — docs/MEMORY.md §2.13, diag_raw_string_in_value.)
$ `stdlib/core/string.nu`

: Bag { [i items i tag }

@ main → i {
    : ~ Bag out @ Bag { [i | 0] 500 }
    ? > ( nurl_str_len `ab` ) 1 {
        : Bag tmp @ Bag { [i | 1 2 3] 201 }
        = out tmp
    } {}
    ( nurl_print_int . out tag ) ( nurl_print `\n` )
    ^ 0
}
