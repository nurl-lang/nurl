// A library handle's copy hook makes every copy of the handle, so it may
// not hand back its argument, whole or in part: each copy would be a
// second owner of one value, read after its caller frees it (agora #334).
// The message points at a counted share or a copy of each field.

$ `stdlib/core/vec.nu`

: X { ( Vec i ) v }

@ X_drop sink X x → v { ( vec_free [i] . x v ) }

@ X_clone X x → X { ^ x }

: Y { ( Vec i ) w }

@ Y_drop sink Y y → v { ( vec_free [i] . y w ) }

@ Y_share Y y → Y { ^ @ Y { . y w } }

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    : X x @ X { a }
    : X c ( X_clone x )
    : ( Vec i ) b ( vec_new [i] )
    : Y y @ Y { b }
    : Y d ( Y_share y )
    ^ 0
}
