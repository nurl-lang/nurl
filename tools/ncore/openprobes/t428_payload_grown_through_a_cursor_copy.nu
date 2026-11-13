// map: §2.10 | A2 | rejected | - | agora #428: a view of an option payload kept while the payload grows through a `: ~` copy of a match payload
$ `stdlib/core/string.nu`

: H { String name }

@ main → i {
    : ~ ? H oh @ ?H { T @ H { ( string_from `the option payload name, alive and long enough` ) } }
    : s v ?? oh { T q → ( string_data . q name ) F → `none` }
    ?? oh { T q → { : ~ H c q ( string_push_str . c name `a long tail that forces the buffer to move to a new allocation, surely, yes` ) } F → {} }
    ( nurl_println v )
    ^ 0
}
