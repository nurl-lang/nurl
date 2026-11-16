// map: §2.10 | A2 | rejected | - | agora #557: the task's prelude form - `: S e ( vec_at k 0 )  : String f . e name` across a clear of `. p a` in a later `??`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b ( Vec S ) z }
: | E { A H B H }

@ mkh → H {
    : ( Vec S ) a ( vec_new [S] )
    ( vec_push [S] a @ S { ( string_from `a heap string long enough to own a buffer on the heap, surely` ) 1 } )
    ^ @ H { a ( vec_new [S] ) ( vec_new [S] ) }
}

@ main → i {
    : ~ E ev @ E { A ( mkh ) }
    : ( Vec S ) k ?? ev { A p → . p a B q → . q a }
    : S e ( vec_at [S] k 0 )
    : String f . e name
    ?? ev { A p → { ( vec_clear [S] . p a ) } B q → {} }
    ( nurl_println_int ( string_len f ) )
    ( nurl_println ( string_data f ) )
    ^ 0
}
