// inout_stores_view.nu — views stored into an inout parameter are read
// while what they point into is still alive; the source ends afterwards.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { ( Vec ( Slice f ) ) fs }

@ add inout H h ( Slice f ) s → v { ( vec_push [( Slice f )] . h fs s ) }

@ add_last ( Slice f ) s inout H h → v { ( vec_push [( Slice f )] . h fs s ) }

@ main → i {
    : ~ ( Vec f ) v ( vec_zeroed [f] 8 )
    : ~ ( Vec f ) u ( vec_zeroed [f] 3 )
    : ~ H h @ H { ( vec_new [( Slice f )] ) }
    ( add h ( slice_from_vec [f] v ) )
    ( add_last ( slice_from_vec [f] u ) h )
    : i r + ( slice_len [f] ( vec_at [( Slice f )] . h fs 0 ) ) ( slice_len [f] ( vec_at [( Slice f )] . h fs 1 ) )
    ( vec_clear [f] v )
    ( nurl_println ( nurl_str_int r ) )
    ^ 0
}
