// H23: generic identity returns its argument; both names consumed.
$ `stdlib/core/vec.nu`

@ ident [T] T x → T { ^ x }

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 3 )
    : ( Vec i ) b ( ident [( Vec i )] a )
    ( vec_free [i] a )
    ( vec_free [i] b )
    ^ 0
}
