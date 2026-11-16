// map: §2.10 | A2 | rejected | - | agora #842: a callee reserving `( rc_get p )` of its option parameter's payload inline - no summary, the caller's slice dangles
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ g ? ( Rc ( Vec i ) ) o → v {
    ?? o { T p → { ( vec_reserve [i] ( rc_get [( Vec i )] p ) 4096 ) } F → {} }
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ( Rc ( Vec i ) ) r ( rc_new [( Vec i )] xs )
    : ~ ? ( Rc ( Vec i ) ) o @ ?( Rc ( Vec i ) ) { T r }
    ?? o {
        T p → {
            : ( Slice i ) sl ( slice_from_vec [i] ( rc_get [( Vec i )] p ) )
            ( g o )
            ( nurl_println_int ( slice_at [i] sl 1 ) )
        }
        F → {}
    }
    ^ 0
}
