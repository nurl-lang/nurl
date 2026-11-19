// AGORA-909: a function that pushes through a field read `. b items` of its
// `inout` parameter, called with an argument that holds a view of another
// value, which is read after the call. The view does not reach `b`, so the
// call changes nothing it views. formal/A2 types this program
// (A2/FreshProjWitness.lean, memory safe and leak-free): a field read of a
// binding of the frame's own whose type holds no views is a fresh borrow, so
// the push is an `edit false` and `add` is not through-changing.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { ( Vec i ) items i n }

@ add inout Bag b ( Slice i ) s → i {
    ( vec_push [i] . b items ( slice_at [i] s 0 ) )
    ^ ( vec_len [i] . b items )
}

@ main → i {
    : ~ Bag b @ Bag { ( vec_new [i] ) 3 }
    : ( Vec i ) src ( vec_new [i] )
    ( vec_push [i] src 5 )
    : ( Slice i ) s ( slice_from_vec [i] src )
    ( nurl_println_int ( add b s ) )
    ( nurl_println_int ( slice_at [i] s 0 ) )
    ( nurl_println_int . b n )
    ^ 0
}
