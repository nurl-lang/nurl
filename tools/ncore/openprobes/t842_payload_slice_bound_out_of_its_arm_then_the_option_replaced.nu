// map: §2.10 | A2 | rejected | - | agora #842: `: v ?? o { T q → ( slice_from_vec q ) … }` over a local option, then `= o @ ?( Vec i ) { F }`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [i] xs k ) = k + k 1 }
    : ( Vec i ) ys ( vec_new [i] )
    : ~ ? ( Vec i ) o @ ?( Vec i ) { T xs }
    : ( Slice i ) v ?? o { T q → ( slice_from_vec [i] q ) F → ( slice_from_vec [i] ys ) }
    = o @ ?( Vec i ) { F }
    ( nurl_println_int ( slice_at [i] v 1 ) )
    ^ 0
}
