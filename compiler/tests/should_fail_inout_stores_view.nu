// should_fail_inout_stores_view.nu — a callee that stores a view argument
// into its inout parameter makes the caller's value hold a view of what
// that argument points into: ending the source leaves it dangling.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { ( Vec ( Slice f ) ) fs }

@ add inout H h ( Slice f ) s → v { ( vec_push [( Slice f )] . h fs s ) }

@ main → i {
    : ~ ( Vec f ) v ( vec_zeroed [f] 8 )
    : ~ H h @ H { ( vec_new [( Slice f )] ) }
    ( add h ( slice_from_vec [f] v ) )
    ( vec_clear [f] v )
    ^ ( slice_len [f] ( vec_at [( Slice f )] . h fs 0 ) )
}
