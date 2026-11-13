// enum_with_a_number_before_its_buffer_given_a_lend_beside_a_cursor_runs_clean: `: | E2 { EN EA i String }`: `= o ( vec_at rs 0 )` and `= o ( mk )` with a `: ~ E2 c o` cursor, then a unit variant assigned.
// Closed (agora #366): the hand-over and the keep keyed an enum by its first payload slot whatever the variant, the number 3 here, which another value holds too — answered "no key", the owner kept its old value back for good (a leak). An enum is keyed by its active variant's first payload that is its own buffer (mem_enum_variant_key), the String, null for a variant that has none.
// map: §7.6 | A2 | runs-clean | - | agora #366: an enum whose variant holds a number before its buffer, given a lend beside a cursor
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E2 { EN EA i String }

@ mk → E2 { ^ @ E2 { EA 3 ( string_from `an enum payload string, long enough for the heap` ) } }

@ main → i {
    : ( Vec E2 ) rs ( vec_new [E2] )
    ( vec_push [E2] rs ( mk ) )
    : ~ E2 o ( mk )
    : ~ E2 c o
    = o ( vec_at [E2] rs 0 )
    = o ( mk )
    : E2 u EN
    = o u
    ^ 0
}
