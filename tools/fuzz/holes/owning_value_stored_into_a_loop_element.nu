// owning_value_stored_into_a_loop_element: `~ p ps { = . p name ( string_from … ) }` — the loop binds a copy of each element, so the store landed in that copy, the Vec kept its old value and the new String leaked.
// Closed: an owning value stored into a borrowed copy (a by-value parameter, a loop element, a closure's by-value capture) is refused with the fix named (gen_field_store, __fs_borrowed_copy_kind; agora #488).
// map: §5.4 | A2 | rejected | - | agora #488: an owning value stored into a field of a `~` loop element (a copy) leaked
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ main → i {
    : ( Vec P ) ps ( vec_new [P] )
    ( vec_push [P] ps @ P { ( string_from `old, a name long enough for a heap buffer` ) 1 } )
    ~ p ps { = . p name ( string_from `new, a name long enough for a heap buffer` ) }
    ( nurl_println ( string_data . ( vec_at [P] ps 0 ) name ) )
    ^ 0
}
