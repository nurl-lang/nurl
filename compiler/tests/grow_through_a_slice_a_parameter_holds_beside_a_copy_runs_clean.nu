// AGORA-933: the accepted twins of the refused calls. The callee grows a
// Vec it reaches through a slice its parameter holds; the caller passes a
// copy that owns its data beside it, and reads its own view only before the
// call. Both run clean, and the grow is seen through the Vec.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f ( Vec ( Slice ( Vec i ) ) ) vv ( Slice i ) s2 → i {
    : ( Slice ( Vec i ) ) e ( vec_at [( Slice ( Vec i ) )] vv 0 )
    : ~ ( Vec i ) b ( slice_at [( Vec i )] e 0 )
    ( vec_push [i] b 7 )
    ^ + ( slice_at [i] s2 0 ) ( vec_len [i] b )
}

@ main → i {
    : ( Vec ( Vec i ) ) w ( vec_new [( Vec i )] )
    : ( Vec i ) w0 ( vec_new [i] )
    ( vec_push [i] w0 5 )
    ( vec_push [( Vec i )] w w0 )
    : ~ ( Vec ( Slice ( Vec i ) ) ) vv ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] vv ( slice_from_vec [( Vec i )] w ) )
    : ( Slice i ) s2 ( slice_from_vec [i] ( vec_at [( Vec i )] w 0 ) )
    ( nurl_println_int ( slice_at [i] s2 0 ) )
    : ( Vec i ) c ( slice_to_vec [i] s2 )
    ( nurl_println_int ( f vv ( slice_from_vec [i] c ) ) )
    ( nurl_println_int ( vec_len [i] ( vec_at [( Vec i )] w 0 ) ) )
    ^ 0
}
