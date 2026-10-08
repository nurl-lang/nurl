// H45: a Slice of a Vec read out of a Vec of Vecs; the outer Vec is freed; the Slice is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    : ( Vec i ) inner ( vec_new [i] )
    ( vec_push [i] inner 7 )
    ( vec_push [( Vec i )] vv inner )
    ?? ( vec_get [( Vec i )] vv 0 ) {
        T e → {
            : ( Slice i ) s ( slice_from_vec [i] e )
            ( vec_free [( Vec i )] vv )
            ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F → {} }
        }
        F → {}
    }
    ^ 0
}
