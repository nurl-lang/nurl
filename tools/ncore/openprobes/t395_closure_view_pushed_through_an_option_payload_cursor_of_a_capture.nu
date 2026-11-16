// map: §2.11 | A2 | rejected | - | agora #395: inside a closure, a view of a closure local pushed through `?? ov { T w → ( vec_push w … ) }` of a captured option
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ?( Vec s ) ov @ ?( Vec s ) { T ( vec_new [s] ) }
    : ( @ v ) f \ → v {
        : String loc ( string_from `a heap string freed when the closure returns, long enough for the heap` )
        ?? ov { T w → ( vec_push [s] w ( string_data loc ) ) F → {} }
    }
    ( f )
    ?? ov { T w → ( nurl_println ( vec_at [s] w 0 ) ) F → {} }
    ^ 0
}
