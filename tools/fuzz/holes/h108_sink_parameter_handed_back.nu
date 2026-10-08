// H108: a `sink` parameter handed back (`^ x`) was read as a second name of the caller's argument — but the argument went into the call, so the result was nobody's and leaked (a builder that takes and returns its value).
$ `stdlib/core/string.nu`

: Cfg { String name i port }

@ with_port sink Cfg c i p → Cfg {
    : ~ Cfg out c
    = . out port p
    ^ out
}

@ main → i {
    : Cfg c1 @ Cfg { ( string_from `server` ) 80 }
    : Cfg c2 ( with_port c1 8080 )
    ( nurl_print_int . c2 port ) ( nurl_print `\n` )
    ^ 0
}
