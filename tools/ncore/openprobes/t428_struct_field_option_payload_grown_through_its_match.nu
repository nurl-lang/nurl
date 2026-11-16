// map: §2.10 | A2 | rejected | - | agora #428: a view of a struct field option's payload kept while `?? . st o` grows it
$ `stdlib/core/string.nu`

: H { String name }
: St { ? H o }

@ main → i {
    : ~ St st @ St { @ ?H { T @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } } }
    : s v ?? . st o { T q → ( string_data . q name ) F → `none` }
    ?? . st o { T q → { ( string_push_str . q name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } F → {} }
    ( nurl_println v )
    ^ 0
}
