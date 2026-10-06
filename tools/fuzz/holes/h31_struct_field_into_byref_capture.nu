// H31: the same copy into a binding a closure captured by reference.
$ `stdlib/core/string.nu`

: Resp { s body i code }

@ main → i {
    : ~ Resp out @ Resp { `none` 500 }
    : ( @ v ) f \ → v {
        : Resp tmp @ Resp { ( nurl_str_cat `escaped-` `field` ) 201 }
        = out tmp
    }
    ( f )
    ( nurl_print . out body ) ( nurl_print `\n` )
    ^ 0
}
