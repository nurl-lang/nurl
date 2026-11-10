// diag_owned_fields_alias.nu — a struct whose raw string field it owns (an
// `unsafe` function gave it a fresh one), copied to a binding that outlives
// it. `tmp`'s field is freed when `tmp`'s block ends; `out` would still
// point at it. The fix: an owning field type (a String), so the value
// moves, or build the struct where it is kept. (Safe code cannot make such
// a struct at all — docs/MEMORY.md §2.13, diag_raw_string_in_value — and a
// slice field is the struct's own, which moves: slice_owned_value.nu.)
$ `stdlib/core/string.nu`

: Bag { s name i tag }

unsafe @ mk i tag → Bag { ^ @ Bag { ( nurl_str_cat `a` `b` ) tag } }

@ main → i {
    : ~ Bag out ( mk 500 )
    ? > ( nurl_str_len `ab` ) 1 {
        : Bag tmp ( mk 201 )
        = out tmp
    } {}
    ( nurl_print_int . out tag ) ( nurl_print `\n` )
    ^ 0
}
