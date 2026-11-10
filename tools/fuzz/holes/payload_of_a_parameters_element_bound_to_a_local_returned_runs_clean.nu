// payload_of_a_parameters_element_bound_to_a_local_returned_runs_clean:
// `: ( Vec String ) v ( vec_at [( Vec String )] pvv 0 )  ?? ( vec_get [String] v 0 )
// { T e → { ^ e } … }`, pvv a parameter: v owns nothing on this run (a lend of
// pvv's element), yet `^ e` answered "owned" and the caller freed pvv's element
// a second time (heap-use-after-free in nurl_vec_drop). Closed (agora #560): a
// payload lent out of a root that owned nothing on the run answers "lent".
// map: §7.6 | A2 | runs-clean | - | `^ e` of a vec_get payload of a local bound to a parameter's element: answered owned, the caller freed the element twice (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`
$ `stdlib/std/panic.nu`

@ first ( Vec ( Vec String ) ) pvv → String {
    : ( Vec String ) v ( vec_at [( Vec String )] pvv 0 )
    ?? ( vec_get [String] v 0 ) { T e → { ^ e } F → { ^ ( string_new ) } }
}

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ( Vec String ) in0 ( vec_new [String] )
    ( vec_push [String] in0 ( string_from `lend local` ) )
    ( vec_push [( Vec String )] vv in0 )
    : String r ( first vv ) ( nurl_println ( string_data r ) )
    ( nurl_println ( string_data ( vec_at [String] ( vec_at [( Vec String )] vv 0 ) 0 ) ) )
    ^ 0
}
