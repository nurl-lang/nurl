// defer_vget_return_sees_element.nu — agora #561: `^ e` of a `vec_get`
// payload of a local Vec under a defer armed before it. The defer runs
// while the Vec still holds the element (spec §5.3), so it prints 3, then
// the caller prints abc. The `^` took the element out first, and the
// defer printed 0.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ first → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `abc` ) )
    ; { ( nurl_println_int ( string_len ( vec_at [String] vs 0 ) ) ) }
    ?? ( vec_get [String] vs 0 ) { T e → { ^ e } F → { ^ ( string_new ) } }
}

@ main → i {
    : String r ( first )
    ( nurl_println ( string_data r ) )
    ^ 0
}
