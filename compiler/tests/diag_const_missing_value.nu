// diag_const_missing_value.nu — a global constant with no value used to
// advance one token and return, defining nothing. The token it swallowed
// was the next declaration's '@', so the compiler reported "unexpected
// 'main' at the top level" on the following line and blamed unbalanced
// braces. The declaration that is actually incomplete is this one.

: i MAX_CONN

@ main → i {
    ( nurl_print ( nurl_str_int MAX_CONN ) )
    ^ 0
}
