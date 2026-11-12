// owning_value_stored_into_a_closure_capture: `\ i k → v { = . a name ( string_from … ) }` over a captured `: App a` — the body works on its own copy, made at each call; the binding outside kept its old value and the new String leaked, without a word.
// Closed: refused, naming the mutable binding a closure captures by pointer (gen_field_store, __fs_borrowed_copy_kind; agora #643).
// map: §7.2 | A2 | rejected | - | agora #643: an owning value stored into a closure's by-value capture leaked
$ `stdlib/core/string.nu`

: App { String name i n }

@ main → i {
    : App a @ App { ( string_from `the first name, also long enough to live on the heap` ) 1 }
    : ( @ v i ) f \ i k → v { = . a name ( string_from `a replacement name that is long enough to live on the heap` ) }
    ( f 1 )
    ( nurl_println ( string_data . a name ) )
    ^ 0
}
