// record_with_a_unit_variant_first_given_a_new_value_beside_a_cursor_runs_clean: `: R { E e String s }` bound from a call whose `E` is a unit variant made by name, a `: ~ R c o` cursor, `= o ( mk )`.
// Closed (agora #366), as record_keyed_past_a_unit_variant_field_handed_to_a_cursor_runs_clean: the unit variant's payload slot was undef.
// map: §7.6 | A2 | runs-clean | - | agora #366: a record with a unit-variant field given a new value beside a cursor
$ `stdlib/core/string.nu`

: | E { EA EB String }
: R { E e String s }

@ mk → R { : E u EA ^ @ R { u ( string_from `a fresh record string, long enough for the heap` ) } }

@ main → i {
    : ~ R o ( mk )
    ?? . o e { EA → { ( nurl_println `EA` ) } EB x → { ( nurl_println `EB` ) } }
    ( nurl_println_int ( string_len . o s ) )
    : ~ R c o
    = o ( mk )
    ^ 0
}
