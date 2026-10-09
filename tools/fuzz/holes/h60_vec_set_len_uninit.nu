// H60: vec_set_len exposes uninitialised String elements to safe code.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) xs ( vec_with_cap [String] 8 )
    : b ok ( vec_set_len [String] xs 8 )
    ?? ( vec_get [String] xs 5 ) { T e → { ( nurl_println_int ( string_len e ) ) } F → {} }
    ^ 0
}
