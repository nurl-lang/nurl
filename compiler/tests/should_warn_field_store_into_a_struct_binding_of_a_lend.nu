// should_warn_field_store_into_a_struct_binding_of_a_lend.nu — agora #798.
//
// `: App e ( vec_at [App] ps 0 )` binds a COPY of the element vec_at lends:
// a field store into `e` lands in that copy, and the Vec keeps its old
// value. It ran clean and printed the old values without a word. Both
// stores below are warned, an owning one and a scalar one; the binding owns
// what it is given by its run-time flag, so nothing leaks.
//
// Not warned: an owned copy (`mem_dup`), a binding given a new value of its
// own by `=` before the store, and a struct a call made fresh.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: App { String name i n }

@ mk → App { ^ @ App { ( string_from `made by mk, long enough for a heap buffer` ) 3 } }

@ main → i {
    : ( Vec App ) ps ( vec_new [App] )
    ( vec_push [App] ps @ App { ( string_from `the old name, long enough for a heap buffer` ) 1 } )
    // Warned: the store lands in e's copy.
    : App e ( vec_at [App] ps 0 )
    = . e name ( string_from `the new name, long enough for a heap buffer` )
    = . e n 7
    ( nurl_println ( string_data . ( vec_at [App] ps 0 ) name ) )
    ( nurl_println_int . ( vec_at [App] ps 0 ) n )
    // Not warned: an owned copy is a value of its own.
    : App d ( mem_dup ( vec_at [App] ps 0 ) )
    = . d n 8
    ( nurl_println_int . d n )
    // Not warned: `=` gave the binding a value of its own first.
    : ~ App r ( vec_at [App] ps 0 )
    = r @ App { ( string_from `a fresh value, long enough for a heap buffer` ) 2 }
    = . r n 9
    ( nurl_println_int . r n )
    // Not warned: a struct the call made.
    : App m ( mk )
    = . m n 10
    ( nurl_println_int . m n )
    ^ 0
}
