// map: §2.11 | A2 | rejected | - | agora #395: inside a closure, a view of a closure local stored through `( vec_at vv 0 )`, an element borrow of a capture
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    : ( @ v ) f \ → v {
        : String loc ( string_from `a heap string freed when the closure returns, long enough for the heap` )
        : ( Vec s ) w ( vec_at [( Vec s )] vv 0 )
        ( vec_push [s] w ( string_data loc ) )
    }
    ( f )
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}
