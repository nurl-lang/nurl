// should_fail_inout_later_stores_view.nu — the owner passed inout need not
// come first: a view handed beside it, to a callee that keeps the view in
// it, makes it hold that view all the same.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { ( Vec ( Slice f ) ) fs }

@ add ( Slice f ) s inout H h → v { ( vec_push [( Slice f )] . h fs s ) }

@ main → i {
    : ~ ( Vec f ) v ( vec_zeroed [f] 8 )
    : ~ H h @ H { ( vec_new [( Slice f )] ) }
    ( add ( slice_from_vec [f] v ) h )
    ( vec_clear [f] v )
    ^ ( slice_len [f] ( vec_at [( Slice f )] . h fs 0 ) )
}
