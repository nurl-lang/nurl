// struct_of_an_option_moved_by_assignment_then_its_source_given_a_new_value_runs_clean: a struct whose only owned field is a `?String`, `= t a` then `= a b`, `t` and `a` read after.
// Closed (agora #634): `t` was a cursor over `a`, to be handed a's value at `= a b` by the identity of the value's first buffer — and a struct that holds its String in an option has none to compare, so nothing was handed over: a's value was dropped under `t` (heap-use-after-free, no loop needed). `= t a` is a move now, and needs no identity.
// map: §2.2 | A2 | runs-clean | - | agora #634: a struct with no buffer to tell it by, moved by assignment: its value was dropped at the source's next assignment
$ `stdlib/core/string.nu`

: Q { i n ? String name }

@ mk s x → Q { ^ @ Q { 1 @ ?String { T ( string_from x ) } } }

@ show Q q → v { ?? . q name { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ Q a ( mk `the first string, long enough for the heap, yes` )
    : ~ Q b ( mk `the second string, long enough for the heap, yes` )
    : ~ Q t ( mk `the third string, long enough for the heap, yes` )
    = t a
    = a b
    ( show t )
    ( show a )
    ^ 0
}
