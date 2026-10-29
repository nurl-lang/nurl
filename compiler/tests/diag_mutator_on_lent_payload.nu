// diag_mutator_on_lent_payload.nu — a mutator called on a value an
// accessor lends — `( vec_push [i] ( rc_get [( Vec i )] r ) x )` — changes
// what that accessor lends from (agora #169): a view of the payload taken
// before it, or a walk over it, ends; through a clone of the Rc too, since
// every clone shares one payload.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ view_then_push → v {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Rc ( Vec i ) ) r ( rc_new [( Vec i )] v )
    : ( Slice i ) sl ( slice_from_vec [i] ( rc_get [( Vec i )] r ) )
    ( vec_push [i] ( rc_get [( Vec i )] r ) 2 )
    ( nurl_println_int ( slice_at [i] sl 0 ) )
}

@ view_then_push_through_a_clone → v {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Rc ( Vec i ) ) r ( rc_new [( Vec i )] v )
    : ( Rc ( Vec i ) ) r2 ( rc_clone [( Vec i )] r )
    : ( Slice i ) sl ( slice_from_vec [i] ( rc_get [( Vec i )] r ) )
    ( vec_push [i] ( rc_get [( Vec i )] r2 ) 2 )
    ( nurl_println_int ( slice_at [i] sl 0 ) )
}

@ walked_while_a_closure_pushes → v {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Rc ( Vec i ) ) r ( rc_new [( Vec i )] v )
    : ( Rc ( Vec i ) ) r2 ( rc_clone [( Vec i )] r )
    ( vec_each [i] ( rc_get [( Vec i )] r ) \ i x → v { ( vec_push [i] ( rc_get [( Vec i )] r2 ) x ) } )
}

@ main → i { ^ 0 }
