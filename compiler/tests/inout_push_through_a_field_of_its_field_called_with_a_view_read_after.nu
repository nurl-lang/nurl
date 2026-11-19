// AGORA-909: a function that pushes through a field of a field,
// `. . o bag items`, of its `inout` parameter, called with an argument that
// holds a view of another value, which is read after the call. The view does
// not reach `o`, so the call changes nothing it views. formal/A2 types this
// program (A2/FreshNestWitness.lean, memory safe and leak-free): each field
// read is fresh (the first of the frame's own binding, the second of a fresh,
// held-fresh borrow, both of types that hold no views), so the push is an
// `edit false` and `add` is not through-changing.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { ( Vec i ) items i n }
: Box { Bag bag i tag }

@ add inout Box o ( Slice i ) s → i {
    ( vec_push [i] . . o bag items ( slice_at [i] s 0 ) )
    ^ ( vec_len [i] . . o bag items )
}

@ main → i {
    : ~ Box o @ Box { @ Bag { ( vec_new [i] ) 3 } 9 }
    : ( Vec i ) src ( vec_new [i] )
    ( vec_push [i] src 5 )
    : ( Slice i ) s ( slice_from_vec [i] src )
    ( nurl_println_int ( add o s ) )
    ( nurl_println_int ( slice_at [i] s 0 ) )
    ( nurl_println_int . o tag )
    ^ 0
}
