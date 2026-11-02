// closure_called_with_the_option_capture_it_replaces: the same with a `?String` capture.
// Closed: a closure called with a binding it gives a new value by name (a capture it assigns, whole or by a field) is refused at the call, as `( put x x )` with an `inout` is: inside, the parameter and the capture are one value (agora #339).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #339: the same with a `?String` capture
$ `stdlib/core/string.nu`

@ id ? String s → ?String {
    ^ s
}

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owner string long enough for the heap` ) }
    : ( @ v ? String ) c \ ? String p → v { = o ( id p ) }
    ( c o )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
