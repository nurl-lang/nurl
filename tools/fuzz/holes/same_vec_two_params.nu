// same_vec_two_params: one Vec passed to two parameters; the callee clears one while it holds a borrow from the other.
// map: CallT.args | A1 | rejected | h67 | one Vec passed to two params; callee clears one while borrowing other
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ f ( Vec String ) a ( Vec String ) b → i {
    ^ ?? ( vec_get [String] b 0 ) { T e → { ( vec_clear [String] a ) ( string_len e ) } F → 0 }
}

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `a long element string on the heap` ) )
    ( nurl_println_int ( f xs xs ) )
    ^ 0
}
