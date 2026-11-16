// map: §2.11 | A2 | rejected | - | agora #395: inside a closure, a view of a closure local stored through `( id vs )`, a borrow of a capture
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ( Vec s ) x → ( Vec s ) { ^ x }

@ main → i {
    : ( Vec s ) vs ( vec_new [s] )
    : ( @ v ) f \ → v {
        : String loc ( string_from `a heap string freed when the closure returns, long enough for the heap` )
        : ( Vec s ) w ( id vs )
        ( vec_push [s] w ( string_data loc ) )
    }
    ( f )
    ( nurl_println ( vec_at [s] vs 0 ) )
    ^ 0
}
