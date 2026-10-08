// sink_handed_back.nu — a `sink` parameter handed back (`^ x`, a builder
// that takes its value and returns it changed). The callee owns what it
// was handed, so what comes back is the caller's own new value — not a
// second name of the argument, which went into the call. Read as one, the
// result was nobody's and leaked (h108), when the callee was compiled
// before its caller; a callee compiled after it was right all along.
// Bound and temporary arguments, a String, a Vec and a struct of owned
// fields, both orders. The sanitizer corpus runs this with leak detection.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Cfg { String name i port }

@ with_port sink Cfg c i p → Cfg {
    : ~ Cfg out c
    = . out port p
    ^ out
}

@ ident sink String x → String { ^ x }

@ grow sink ( Vec i ) v i x → ( Vec i ) {
    ( vec_push [i] v x )
    ^ v
}

@ before → i {
    : Cfg c1 @ Cfg { ( string_from `server` ) 80 }
    : Cfg c2 ( with_port c1 8080 )
    : Cfg c3 ( with_port @ Cfg { ( string_from `tmp` ) 1 } 2 )
    : String a ( string_from `abcd` )
    : String r ( ident a )
    : String t ( ident ( string_from `xyz` ) )
    : ( Vec i ) v ( vec_new [i] )
    : ( Vec i ) w ( grow v 7 )
    ^ + + + + . c2 port . c3 port ( string_len r ) ( string_len t ) ( vec_len [i] w )
}

@ after → i {
    : String a ( string_from `abcd` )
    : String r ( ident_later a )
    : Cfg c1 @ Cfg { ( string_from `server` ) 80 }
    : Cfg c2 ( port_later c1 9090 )
    ^ + ( string_len r ) . c2 port
}

@ ident_later sink String x → String { ^ x }

@ port_later sink Cfg c i p → Cfg {
    : ~ Cfg out c
    = . out port p
    ^ out
}

@ main → i {
    ( nurl_print_int ( before ) ) ( nurl_print `\n` )
    ( nurl_print_int ( after ) ) ( nurl_print `\n` )
    ^ 0
}
