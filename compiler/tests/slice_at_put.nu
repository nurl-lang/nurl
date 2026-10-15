// slice_at / slice_put / slice_prefix: the bounds-checked indexing a loop
// over several Vecs wants, writing one while reading others.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`

@ axpy f a ( Vec f ) x ( Vec f ) y → v {
    : ( Slice f ) xs ( slice_from_vec [f] x )
    : ( Slice f ) ys ( slice_from_vec [f] y )
    : i n ( slice_len [f] xs )
    : ~ i k 0
    ~ < k n { ( slice_put [f] ys k + * a ( slice_at [f] xs k ) ( slice_at [f] ys k ) ) = k + k 1 }
}

@ main → i {
    : ( Vec f ) x ( vec_new [f] )
    : ( Vec f ) y ( vec_new [f] )
    : ~ i k 0
    ~ < k 5 { ( vec_push [f] x # f k ) ( vec_push [f] y 1.0 ) = k + k 1 }
    ( axpy 2.0 x y )
    = k 0
    ~ < k 5 { ( nurl_print_int # i ( vec_at [f] y k ) ) ( nurl_print ` ` ) = k + k 1 }
    ( nurl_println `` )
    // Owning elements: a store drops the element it replaces.
    : ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `first, long enough to own a buffer` ) )
    ( vec_push [String] names ( string_from `second` ) )
    : ( Slice String ) ns ( slice_from_vec [String] names )
    ( slice_put [String] ns 0 ( string_from `replaced` ) )
    ( nurl_println ( string_data ( slice_at [String] ns 0 ) ) )
    // One length for parallel columns.
    : ( Slice f ) p ( slice_prefix [f] ( slice_from_vec [f] x ) 3 )
    ( nurl_println_int ( slice_len [f] p ) )
    ( nurl_println_int # i ( slice_at [f] p 2 ) )
    ^ 0
}
