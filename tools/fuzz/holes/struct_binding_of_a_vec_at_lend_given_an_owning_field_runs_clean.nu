// struct_binding_of_a_vec_at_lend_given_an_owning_field_runs_clean: `: App e ( vec_at [App] ps 0 )` then `= . e name ( string_from … )`, once and in a loop — the store lands in e's copy (warned as lost, agora #798); the binding owns the new String by its run-time flag, so nothing leaks and the Vec's own name is released once.
// map: §5.4 | A2 | runs-clean | - | agora #798: a field store into a struct binding of a vec_at lend is warned as lost; it must keep running clean
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: App { String name i n }

@ main → i {
    : ( Vec App ) ps ( vec_new [App] )
    ( vec_push [App] ps @ App { ( string_from `the old name, long enough for a heap buffer` ) 1 } )
    : App e ( vec_at [App] ps 0 )
    = . e name ( string_from `the new name, long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 3 {
        : App f ( vec_at [App] ps 0 )
        = . f name ( string_from `a name per round, long enough for a heap buffer` )
        = k + k 1
    }
    ( nurl_println ( string_data . ( vec_at [App] ps 0 ) name ) )
    ^ 0
}
