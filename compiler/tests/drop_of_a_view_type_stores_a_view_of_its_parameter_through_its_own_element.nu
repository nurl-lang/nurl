// Agora #909's own example (Agora #3932): a `% Drop` of a struct that holds
// a slice, whose code stores `. d s`, the view its caller lent it, into
// `( vec_at loc 0 )` of a local it made. The store reaches only memory the
// destructor owns; what it stores views the caller's memory, which outlives
// the call. formal/A2 types such a store `edit false` (StmtT.editBV through a
// fresh borrow that is not held-fresh: a call lifts it, and `loc`, with all
// the arguments hold), so the destructor is not through-changing:
// A2/ParamViewWitness.lean, main_safe and main_no_leak.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: V { ( Slice i ) s i k }

% Drop V { @ drop V d → v {
        : ( Vec ( Vec ( Slice i ) ) ) loc ( vec_new [( Vec ( Slice i ) )] )
        ( vec_push [( Vec ( Slice i ) )] loc ( vec_new [( Slice i )] ) )
        ( vec_push [( Slice i )] ( vec_at [( Vec ( Slice i ) )] loc 0 ) . d s )
        ( nurl_println_int ( slice_at [i] ( vec_at [( Slice i )] ( vec_at [( Vec ( Slice i ) )] loc 0 ) 0 ) 0 ) )
    } }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    : k 3
    : x @ V { s k }
    ^ 0
}
