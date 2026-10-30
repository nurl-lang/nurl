// generic_returns_param: generic identity returns its argument; both names consumed.
// map: CallT.summary | A1 | rejected | h23 | identity result lends from a; a freed then result freed: double free
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
