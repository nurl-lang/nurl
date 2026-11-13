// owning_value_stored_into_a_by_value_param_handed_back: `@ rename App a → App { = . a name ( string_from … ) ^ a }` — the store lands in the function's own copy of the caller's value; handed back, the result was taken for a lend and the new String leaked.
// Closed: refused, naming `inout` and `sink` (gen_field_store, __fs_borrowed_copy_kind; agora #643).
// map: §7.2 | A2 | rejected | - | agora #643: an owning value stored into a by-value parameter's field, the copy handed back, leaked
$ `stdlib/core/string.nu`

: App { String name i n }

@ rename App a → App { = . a name ( string_from `a replacement name that is long enough to live on the heap` ) ^ a }

@ main → i {
    : App a @ App { ( string_from `the first name, also long enough to live on the heap` ) 1 }
    : App b ( rename a )
    ( nurl_println ( string_data . b name ) )
    ^ 0
}
