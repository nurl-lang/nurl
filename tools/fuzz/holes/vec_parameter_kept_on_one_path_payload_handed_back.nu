// vec_parameter_kept_on_one_path_payload_handed_back: `?? ( vec_get [String] p 0 ) { T e → { ^ e } … }`, p kept on another path: vec_get answers per call, but lends a part of p on every run
// Closed: a `:` binding's lend out of a parameter the function takes over on another path is judged at `^` as the returned call is (agora #743): parked, refused at module end (__pfo_bind_lends, agora #765). A callee that answers per call and may hand the argument back whole still hands its source over by identity (agora #459).
// main 9052104: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #765: a vec_get payload of a kept parameter handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String name i n }

@ f ( Vec ( Vec String ) ) log ( Vec String ) p b keep → String { ? keep { ( vec_push [( Vec String )] log p ) ^ ( string_from `kept` ) } {} ?? ( vec_get [String] p 0 ) { T e → { ^ e } F → {} } ^ ( string_from `none` ) }

@ main → i {
    : ~ ( Vec ( Vec String ) ) log ( vec_new [( Vec String )] )
    : ~ ( Vec String ) v1 ( vec_new [String] ) ( vec_push [String] v1 ( string_from `element string long enough for heap a` ) )
    : String a ( f log v1 F ) ( nurl_println ( string_data a ) )
    ^ 0
}
