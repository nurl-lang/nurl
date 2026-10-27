// inout_borrow_takeover.nu — a `: ~` copy of a value with a `% Drop` of its
// own, taken from a local that owns it outright (a `let`, a `sink`
// parameter), holds that local's drop: handed `inout` to a callee that gives
// it a new value, it becomes the owner, and the local is moved (agora
// #135). Each value is released once, the renamed one by the copy.
// diag_inout_borrow_replaced shows the copies that may not go so: one of a
// parameter, a field, a lend, a cursor over a String or a Vec, and the
// local read after the call.
$ `stdlib/core/string.nu`

: Res {
    String name
    i n
}

% Drop Res { @ drop Res r → v { ( nurl_println ( string_data . r name ) ) } }

@ rename inout Res r → v {
    = . r name ( string_from `renamed` )
    = . r n + . r n 1
}

@ run sink Res start → i {
    : ~ Res r start
    ( rename r )
    ( rename r )
    ^ . r n
}

@ local → i {
    : Res s0 @ Res { ( string_from `local` ) 0 }
    : ~ Res r s0
    ( rename r )
    ^ . r n
}

@ main → i {
    : i a ( run @ Res { ( string_from `parameter` ) 0 } )
    : i b ( local )
    ( nurl_print_int + a b ) ( nurl_print `\n` )
    ^ 0
}
