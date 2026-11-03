// diag_closure_called_with_the_capture_it_replaces.nu — a closure that
// gives its by-pointer capture 'o' a new value, called as '( c o )'.
// Inside, the parameter and the capture are one value, so the
// replacement freed what the parameter still was (heap-use-after-free).
// The call is refused as '( put x x )' with an 'inout' is (agora #339).
$ `stdlib/core/string.nu`

@ same String s → String {
    ^ s
}

@ main → i {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    : ( @ v String ) c \ String p → v { = o ( same p ) }
    ( c o )
    ( nurl_println ( string_data o ) )
    ^ 0
}
