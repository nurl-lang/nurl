// owning_value_stored_into_a_closure_parameter: `\ App x → v { = . x name ( string_from … ) }` run on an App, directly or by vec_each — the body's copy of its by-value parameter took the new String and nothing released it; the caller kept its old value. A named function's parameter was refused (AGORA-643); a closure literal's slot carried no parameter-copy mark, so it leaked with no word.
// Closed: refused, naming the closure's `inout` parameter (gen_field_store, __fs_borrowed_copy_kind 5; agora #643).
// map: §7.2 | A2 | rejected | - | agora #643: an owning value stored into a closure literal's by-value parameter leaked
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: App { String name i n }

@ main → i {
    : ( Vec App ) ps ( vec_new [App] )
    ( vec_push [App] ps @ App { ( string_from `the first name, also long enough to live on the heap` ) 1 } )
    ( vec_each [App] ps \ App x → v { = . x name ( string_from `a replacement name that is long enough to live on the heap` ) } )
    ^ 0
}
