// A helper handing back an element a generic accessor lends, called on a
// temporary (h215): the result is part of the temporary, so the caller
// copies it before the temporary is dropped. It used to keep a view of
// the dropped temporary (heap-use-after-free under ASan); the copy is the
// caller's own — growing it leaves the original alone.
$ `stdlib/core/vec.nu`

@ first_of ( Vec ( Vec i ) ) xs → ( Vec i ) { ^ ( vec_at [( Vec i )] xs 0 ) }

@ mk → ( Vec ( Vec i ) ) {
    : ( Vec i ) seed ( vec_new [i] )
    ( vec_push [i] seed 4 )
    : ( Vec ( Vec i ) ) m ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] m seed )
    ^ m
}

@ main → i {
    : ( Vec i ) inner ( first_of ( mk ) )
    ( vec_push [i] inner 9 )
    ( nurl_println_int ( vec_len [i] inner ) )
    ( nurl_println_int ( vec_at [i] inner 1 ) )
    // On a binding the helper lends: the same element, not a copy.
    : ( Vec ( Vec i ) ) kept ( mk )
    ( vec_push [i] ( first_of kept ) 7 )
    ( nurl_println_int ( vec_len [i] ( vec_at [( Vec i )] kept 0 ) ) )
    ^ 0
}
