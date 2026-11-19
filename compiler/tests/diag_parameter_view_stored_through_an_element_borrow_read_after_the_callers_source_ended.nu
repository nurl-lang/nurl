// The refused direction of compiler/tests/drop_of_a_view_type_stores_a_view_of_its_parameter_through_its_own_element.nu
// (Agora #3932): 'keep' stores its borrowed parameter 'p' through
// `( vec_at loc 0 )` of its own local and returns 'loc'. The caller's 'out'
// then holds a view of 'v', so reading it after 'v' ended is refused. The
// formal side records the same: a call lifts an owner of a type that holds
// views with everything its arguments hold (RSetup.heldA), and a store of a
// value that is not the frame's own never leaves its borrow held-fresh
// (A2/ParamViewWitness.lean, edit_false_unfresh_unheld).
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
    }
    ( nurl_println_int ( slice_at [i] ( vec_at [( Slice i )] ( vec_at [( Vec ( Slice i ) )] out 0 ) 0 ) 0 ) )
    ^ 0
}
