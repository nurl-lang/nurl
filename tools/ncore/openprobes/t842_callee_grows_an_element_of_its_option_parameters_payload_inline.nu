// map: §2.10 | A2 | rejected | - | agora #842: a callee pushing into `( vec_at q 0 )` of its option parameter's payload inline - no summary, the caller's element slice dangles
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ g ?( Vec ( Vec i ) ) p → v {
    ?? p { T q → { : ~ i k 0  ~ < k 1000 { ( vec_push [i] ( vec_at [( Vec i )] q 0 ) k ) = k + k 1 } } F → {} }
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv xs )
    : ~ ?( Vec ( Vec i ) ) o @ ?( Vec ( Vec i ) ) { T vv }
    ?? o {
        T q → {
            : ( Slice i ) sl ( slice_from_vec [i] ( vec_at [( Vec i )] q 0 ) )
            ( g o )
            ( nurl_println_int ( slice_at [i] sl 1 ) )
        }
        F → {}
    }
    ^ 0
}
