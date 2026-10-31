// forward_returning_callee: maybe-aliased consume through a forward-declared callee returning its arg.
// map: CallT.summary | A1 | rejected | h01 | callee returns its param; result aliases arg, both freed (double free)
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
