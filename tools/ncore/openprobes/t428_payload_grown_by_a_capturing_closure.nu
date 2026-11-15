// map: §2.11 | A2 | rejected | - | agora #428: a view of an option payload kept while a closure capturing the option grows the payload
$ `stdlib/core/string.nu`

: H { String name }

@ main → i {
    : ~ ? H oh @ ?H { T @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } }
    : s v ?? oh { T q → ( string_data . q name ) F → `none` }
    : ( @ v ) f \ → v { ?? oh { T q → { ( string_push_str . q name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } F → {} } }
    ( f )
    ( nurl_println v )
    ^ 0
}
