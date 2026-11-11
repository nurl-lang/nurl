// diag_lend_through_slice_of_vec_param.nu — agora #594: an element read
// through a Slice a function built over its Vec parameter is part of that
// parameter, so the function lends it: the caller may not clear the Vec
// while it still reads the result (it used to compile, and the read was a
// use after free). What a returned value reaches is followed through the
// view it was read out of.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mkvs → ( Vec String ) {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `hello world slice element number zero` ) )
    ^ vs
}

@ first ( Vec String ) vs → String {
    : ( Slice String ) sl ( slice_from_vec [String] vs )
    ^ ( slice_at [String] sl 0 )
}

@ main → i {
    : ( Vec String ) vs ( mkvs )
    : String r ( first vs )
    ( vec_clear [String] vs )
    ( nurl_println ( string_data r ) )
    ^ 0
}
