// map: §2.10 | A2 | rejected | - | agora #428: a view of a `( vec_at [?H] vs 0 )` payload kept while a second `??` over it grows it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String name }

@ main → i {
    : ~ ( Vec ?H ) vs ( vec_new [?H] )
    ( vec_push [?H] vs @ ?H { T @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } } )
    : s v ?? ( vec_at [?H] vs 0 ) { T q → ( string_data . q name ) F → `none` }
    ?? ( vec_at [?H] vs 0 ) { T q → { ( string_push_str . q name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } F → {} }
    ( nurl_println v )
    ^ 0
}
