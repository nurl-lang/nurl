// map: §2.11 | A2 | rejected | - | agora #395: inside a closure, a view of a closure local pushed into `( box_get bx )` of a capture, an unbound call as the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

@ main → i {
    : ( Box ( Vec s ) ) bx ( box_new [( Vec s )] ( vec_new [s] ) )
    : ( @ v ) f \ → v {
        : String loc ( string_from `a heap string freed when the closure returns, long enough for the heap` )
        ( vec_push [s] ( box_get [( Vec s )] bx ) ( string_data loc ) )
    }
    ( f )
    ( nurl_println ( vec_at [s] ( box_get [( Vec s )] bx ) 0 ) )
    ^ 0
}
