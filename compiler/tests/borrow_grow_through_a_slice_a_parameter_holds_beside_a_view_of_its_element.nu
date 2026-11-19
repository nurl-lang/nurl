// AGORA-933: a callee grows a Vec it reaches through a slice its parameter
// holds, `( slice_at ( vec_at vv 0 ) 0 )` of a `Vec` of slices, and the caller
// passes a view of that same Vec beside it. Inside the call the two are
// unrelated names: the grow moves the element's buffer and the view reads
// freed memory. Before, nurlc accepted it (the callee's summary lost the
// grow at the slice copy `vec_at` hands back); now the call is refused.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f ( Vec ( Slice ( Vec i ) ) ) vv ( Slice i ) s2 → i {
    : ( Slice ( Vec i ) ) e ( vec_at [( Slice ( Vec i ) )] vv 0 )
    : ~ ( Vec i ) b ( slice_at [( Vec i )] e 0 )
    ( vec_reserve [i] b 4096 )
    ^ ( slice_at [i] s2 0 )
}

@ main → i {
    : ( Vec ( Vec i ) ) w ( vec_new [( Vec i )] )
    : ( Vec i ) w0 ( vec_new [i] )
    ( vec_push [i] w0 5 )
    ( vec_push [( Vec i )] w w0 )
    : ~ ( Vec ( Slice ( Vec i ) ) ) vv ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] vv ( slice_from_vec [( Vec i )] w ) )
    : ( Slice i ) s2 ( slice_from_vec [i] ( vec_at [( Vec i )] w 0 ) )
    ( nurl_println_int ( f vv s2 ) )
    ^ 0
}
