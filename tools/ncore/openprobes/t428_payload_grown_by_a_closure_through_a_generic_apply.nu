// map: §2.11 | A2 | rejected | - | agora #428: a view of an option payload kept while `( gapply [?H] f oh )` runs a closure growing it
$ `stdlib/core/string.nu`

: H { String name }

@ gapply [A] ( @ v inout A ) f inout A x → v { ( f x ) }

@ main → i {
    : ~ ? H oh @ ?H { T @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } }
    : s v ?? oh { T q → ( string_data . q name ) F → `none` }
    : ( @ v inout ? H ) f \ inout ? H p → v { ?? p { T q → { ( string_push_str . q name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } F → {} } }
    ( gapply [? H] f oh )
    ( nurl_println v )
    ^ 0
}
