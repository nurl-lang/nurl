// record_keyed_past_a_unit_variant_field_handed_to_a_cursor_runs_clean: `: R { E e String s }` with `E` holding a unit variant first, a `: ~ R c o` cursor, then `= o ( mk )`, and the same with a lend out of a Vec in between.
// Closed (agora #366): a unit variant was built with an undef payload slot, and the hand-over to the cursor keyed the record by that slot — LLVM folded each read of it apart, and both the owner and the cursor were left owning nothing (a leak of both values). A unit variant's slot is zero now, and a record is keyed by its first field that keys, past an enum that may hold a unit variant (__handle_keyed, mem_handle_key).
// map: §7.6 | A2 | runs-clean | - | agora #366: a record whose first owned field is an enum with a unit variant, handed to a cursor
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { EA EB String }
: R { E e String s }

@ mk → R { ^ @ R { EA ( string_from `a fresh record string, long enough for the heap` ) } }

@ main → i {
    : ( Vec R ) rs ( vec_new [R] )
    ( vec_push [R] rs ( mk ) )
    : ~ R o ( mk )
    : ~ R c o
    = o ( vec_at [R] rs 0 )
    = o ( mk )
    ^ 0
}
