// closure_field_store_to_a_single_field_capture_owned: agora #356 — a closure stores an owned String into a field of a captured single-field `: ~` struct: the struct was captured by value, so the write landed in the env's copy, the binding kept its old name and the new one leaked.
// Closed: the root of a field-path store target (`= . p f …`, `= . . h w f …`) counts as assigned, so the closure takes the binding by pointer and the store reaches it (simple_capture_analysis, MEMORY.md §2.3, agora #356).
// main: accepted; printed the old name and LSan reported 88 bytes leaked.
// map: §2.3 | A2 | runs-clean | - | agora #356: a closure storing an owned field of a captured single-field struct
$ `stdlib/core/string.nu`

: P { String name }

@ main → i {
    : ~ P p @ P { ( string_from `the old name, long enough for the heap` ) }
    : ( @ v ) f \ → v { = . p name ( string_from `the new name, also long enough for the heap` ) }
    ( f )
    ( nurl_println ( string_data . p name ) )
    ^ 0
}
