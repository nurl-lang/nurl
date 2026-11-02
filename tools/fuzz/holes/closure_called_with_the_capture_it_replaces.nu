// closure_called_with_the_capture_it_replaces: a closure replacing its by-pointer capture `o`, called as `( c o )`; the replacement frees what the argument still is.
// Closed: a closure called with a binding it gives a new value by name (a capture it assigns, whole or by a field) is refused at the call, as `( put x x )` with an `inout` is: inside, the parameter and the capture are one value (agora #339).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #339: a closure replacing its by-pointer capture `o`, called as `( c o )`; the replacement frees what the argument still is
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
