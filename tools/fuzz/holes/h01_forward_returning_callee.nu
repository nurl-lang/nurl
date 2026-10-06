// H1: maybe-aliased consume through a forward-declared callee returning its arg.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    : ( Vec i ) b ( pass a )
    ( vec_free [i] a )
    ( vec_free [i] b )
    ^ 0
}

@ pass ( Vec i ) x → ( Vec i ) { ^ x }
