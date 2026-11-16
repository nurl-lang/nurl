// map: §2.10 | A2 | rejected | - | agora #842: `^ ?? o { T q → ( slice_from_vec q ) … }` over a local owned option - the slice outlives o
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ leak ( Vec i ) d → ( Slice i ) {
    : ( Vec i ) xs ( vec_new [i] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [i] xs k ) = k + k 1 }
    : ~ ? ( Vec i ) o @ ?( Vec i ) { T xs }
    ^ ?? o { T q → ( slice_from_vec [i] q ) F → ( slice_from_vec [i] d ) }
}

@ main → i {
    : ( Vec i ) d ( vec_new [i] )
    : ( Slice i ) v ( leak d )
    ( nurl_println_int ( slice_at [i] v 1 ) )
    ^ 0
}
