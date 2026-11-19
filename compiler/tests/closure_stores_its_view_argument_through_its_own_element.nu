// AGORA-909's own program (github#2041): a closure handed an argument that
// holds a view stores that view through `( vec_at loc 0 )` of a local it
// made. The store reaches only memory the call owns; what it stores views
// the caller's memory, which outlives the call. formal/A2 types such a
// store `edit false` (StmtT.editBV through a fresh borrow that is not
// held-fresh, Agora #3932), so the closure's code is not through-changing
// and the call may pass a view: A2/ClosureParamViewWitness.lean, memory
// safe and leak-free (there the view is the closure's environment).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : ( @ i ( Slice i ) ) f \ ( Slice i ) x → i {
        : ( Vec ( Vec ( Slice i ) ) ) loc ( vec_new [( Vec ( Slice i ) )] )
        ( vec_push [( Vec ( Slice i ) )] loc ( vec_new [( Slice i )] ) )
        ( vec_push [( Slice i )] ( vec_at [( Vec ( Slice i ) )] loc 0 ) x )
        ^ ( slice_at [i] ( vec_at [( Slice i )] ( vec_at [( Vec ( Slice i ) )] loc 0 ) 0 ) 0 )
    }
    ( nurl_println_int ( f ( slice_from_vec [i] v ) ) )
    ^ 0
}
