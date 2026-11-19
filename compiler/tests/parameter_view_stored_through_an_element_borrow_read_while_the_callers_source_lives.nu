// The control of compiler/tests/diag_parameter_view_stored_through_an_element_borrow_read_after_the_callers_source_ended.nu
// (Agora #3932): the same store of a borrowed parameter through an element
// borrow of the callee's own local, read while the caller's source still
// lives: accepted, and it runs clean.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ keep ( Slice i ) p → ( Vec ( Vec ( Slice i ) ) ) {
    : ( Vec ( Vec ( Slice i ) ) ) loc ( vec_new [( Vec ( Slice i ) )] )
    ( vec_push [( Vec ( Slice i ) )] loc ( vec_new [( Slice i )] ) )
    ( vec_push [( Slice i )] ( vec_at [( Vec ( Slice i ) )] loc 0 ) p )
    ^ loc
}

@ main → i {
    : ~ ( Vec ( Vec ( Slice i ) ) ) out ( vec_new [( Vec ( Slice i ) )] )
    {
        : ( Vec i ) v ( vec_new [i] )
        ( vec_push [i] v 5 )
        = out ( keep ( slice_from_vec [i] v ) )
        ( nurl_println_int ( slice_at [i] ( vec_at [( Slice i )] ( vec_at [( Vec ( Slice i ) )] out 0 ) 0 ) 0 ) )
    }
    ^ 0
}
