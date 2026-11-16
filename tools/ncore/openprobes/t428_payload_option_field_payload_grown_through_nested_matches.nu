// map: §2.10 | A2 | rejected | - | agora #428: a view of an option held in another option's payload kept while nested `??`s grow it
$ `stdlib/core/string.nu`

: H { String name }
: P { ? H inner }

@ main → i {
    : ~ ? P op @ ?P { T @ P { @ ?H { T @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } } } }
    : s v ?? op { T p → ?? . p inner { T q → ( string_data . q name ) F → `none` } F → `none` }
    ?? op { T p → { ?? . p inner { T q → { ( string_push_str . q name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } F → {} } } F → {} }
    ( nurl_println v )
    ^ 0
}
