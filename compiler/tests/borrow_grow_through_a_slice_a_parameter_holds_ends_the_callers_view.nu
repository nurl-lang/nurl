// AGORA-933: a callee grows a Vec it reaches through a slice its parameter
// holds, `( slice_at ( vec_at vv 0 ) 0 )`; the caller's own view of that Vec,
// read after the call, would read freed memory. The call ends it: what
// points into the buffers of the elements of what an argument holds a view
// of ends, as for the argument's own elements.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f ( Vec ( Slice ( Vec i ) ) ) vv → i {
    : ( Slice ( Vec i ) ) e ( vec_at [( Slice ( Vec i ) )] vv 0 )
    : ~ ( Vec i ) b ( slice_at [( Vec i )] e 0 )
    ( vec_reserve [i] b 4096 )
    ^ 0
}

@ main → i {
    : ( Vec ( Vec i ) ) w ( vec_new [( Vec i )] )
    : ( Vec i ) w0 ( vec_new [i] )
    ( vec_push [i] w0 5 )
    ( vec_push [( Vec i )] w w0 )
    : ~ ( Vec ( Slice ( Vec i ) ) ) vv ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] vv ( slice_from_vec [( Vec i )] w ) )
    : ( Slice i ) s2 ( slice_from_vec [i] ( vec_at [( Vec i )] w 0 ) )
    ( nurl_println_int ( f vv ) )
    ( nurl_println_int ( slice_at [i] s2 0 ) )
    ^ 0
}
