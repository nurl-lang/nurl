// map: §2.10 | A2 | rejected | - | agora #606: inside a callee, a struct parameter whose field views another field (vec_clear . p arena, then read . p idx)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: A { ( Vec String ) arena ( Vec s ) idx }

@ bad A p → v {
    ( vec_clear [String] . p arena )
    ( nurl_println ( vec_at [s] . p idx 0 ) )
}

@ main → i {
    : A a @ A { ( vec_new [String] ) ( vec_new [s] ) }
    ( vec_push [String] . a arena ( string_from `a heap string long enough to be on the heap for sure` ) )
    ( vec_push [s] . a idx ( string_data ( vec_at [String] . a arena 0 ) ) )
    ( bad a )
    ^ 0
}
