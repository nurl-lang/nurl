// A binding of a call whose lent argument is itself a lending call
// borrows what the inner call lends (h214). `inner` below is an element
// of an element of `top`; it used to borrow only what the outer vec_at
// was handed directly — a temporary — so it borrowed nothing, and
// releasing `top` left it dangling. The same through a match of such a
// call (`o`'s payload) and through a helper that hands its argument back.
$ `stdlib/core/vec.nu`

@ pick ( Vec ( Vec i ) ) xs → ( Vec ( Vec i ) ) { ^ xs }

@ nested_bind ( Vec ( Vec ( Vec i ) ) ) top0 → i {
    : ( Vec ( Vec ( Vec i ) ) ) top ( vec_clone [( Vec ( Vec i ) )] top0 )
    : ( Vec i ) inner ( vec_at [( Vec i )] ( vec_at [( Vec ( Vec i ) )] top 0 ) 0 )
    ( vec_free [( Vec ( Vec i ) )] top )
    ^ ( vec_len [i] inner )
}

@ nested_match ( Vec ( Vec ( Vec i ) ) ) top0 → i {
    : ( Vec ( Vec ( Vec i ) ) ) top ( vec_clone [( Vec ( Vec i ) )] top0 )
    ?? ( vec_get [( Vec i )] ( vec_at [( Vec ( Vec i ) )] top 0 ) 0 ) {
        T inner → { ( vec_free [( Vec ( Vec i ) )] top ) ^ ( vec_len [i] inner ) }
        F _ → {}
    }
    ^ 0
}

@ nested_helper ( Vec ( Vec i ) ) mid0 → i {
    : ( Vec ( Vec i ) ) mid ( vec_clone [( Vec i )] mid0 )
    : ( Vec i ) inner ( vec_at [( Vec i )] ( pick mid ) 0 )
    ( vec_free [( Vec i )] mid )
    ^ ( vec_len [i] inner )
}

@ main → i { ^ 0 }
