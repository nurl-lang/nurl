// map: §2.10 | A2 | rejected | - | agora #842: a callee reserving `( box_get p )` of its option parameter's payload inline - no summary, the caller's slice dangles
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/box.nu`

@ g ?( Box ( Vec i ) ) o → v {
    ?? o { T p → { ( vec_reserve [i] ( box_get [( Vec i )] p ) 4096 ) } F → {} }
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ( Box ( Vec i ) ) bx ( box_new [( Vec i )] xs )
    : ~ ?( Box ( Vec i ) ) o @ ?( Box ( Vec i ) ) { T bx }
    ?? o {
        T p → {
            : ( Slice i ) sl ( slice_from_vec [i] ( box_get [( Vec i )] p ) )
            ( g o )
            ( nurl_println_int ( slice_at [i] sl 1 ) )
        }
        F → {}
    }
    ^ 0
}
