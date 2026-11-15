// map: §2.10 | A2 | rejected | - | agora #842: `( wr o sl )` - sl a slice of o's `??` payload, wr growing that payload then reading sl
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ wr inout ?( Vec i ) o ( Slice i ) sl → v {
    ?? o { T q → { : ~ i k 0  ~ < k 1000 { ( vec_push [i] q k ) = k + k 1 } } F → {} }
    ( nurl_println_int ( slice_at [i] sl 1 ) )
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ~ ?( Vec i ) o @ ?( Vec i ) { T xs }
    ?? o {
        T q → {
            : ( Slice i ) sl ( slice_from_vec [i] q )
            ( wr o sl )
        }
        F → {}
    }
    ^ 0
}
