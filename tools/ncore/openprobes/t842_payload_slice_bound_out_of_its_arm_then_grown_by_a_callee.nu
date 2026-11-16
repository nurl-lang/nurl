// map: §2.10 | A2 | rejected | - | agora #842: `: v ?? o { T q → ( slice_from_vec q ) … }` over a local option, then `( grow o )` pushes into the payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ grow inout ? ( Vec i ) o → v { ?? o { T q → { : ~ i k 0 ~ < k 1000 { ( vec_push [i] q k ) = k + k 1 } } F → {} } }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ( Vec i ) ys ( vec_new [i] )
    : ~ ? ( Vec i ) o @ ?( Vec i ) { T xs }
    : ( Slice i ) v ?? o { T q → ( slice_from_vec [i] q ) F → ( slice_from_vec [i] ys ) }
    ( grow o )
    ( nurl_println_int ( slice_at [i] v 1 ) )
    ^ 0
}
