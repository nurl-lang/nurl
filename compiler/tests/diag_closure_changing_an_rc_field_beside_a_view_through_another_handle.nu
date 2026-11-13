// diag_closure_changing_an_rc_field_beside_a_view_through_another_handle.nu
// — a closure that changes the Rc a captured struct holds in a field ends
// the views of that payload read through another handle, as the call
// written in place does (Agora #736). `( rc_set [( Vec u )] . h a … )`
// written here was refused: `. h a` may be another handle on the Rc value
// `r2` is. Run as a closure's effect, the field path's Rc types were not
// noted, and the slice read after it through `r2` read freed memory. Each
// function below is refused.
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { ( Rc ( Vec u ) ) a i n }

@ run ( @ v ) f → v {
    ( f )
}

@ shared → ( Rc ( Vec u ) ) {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    ^ ( rc_new [( Vec u )] v0 )
}

// Replaced, the closure called here.
@ replaced → v {
    : ( Rc ( Vec u ) ) r ( shared )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : H h @ H { r 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ( @ v ) f \ → v { ( rc_set [( Vec u )] . h a ( vec_new [u] ) ) }
    ( f )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

// Grown, the closure handed to a function that runs it.
@ grown_by_a_runner → v {
    : ( Rc ( Vec u ) ) r ( shared )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : H h @ H { r 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ( @ v ) f \ → v { ( vec_reserve [u] ( rc_get [( Vec u )] . h a ) 4096 ) }
    ( run f )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

@ main → i {
    ^ 0
}
