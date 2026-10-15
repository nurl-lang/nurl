// should_fail_inout_field_stores_view.nu — the same through a field passed
// inout (`. w h`): the value holding the view is `w`.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { ( Vec ( Slice f ) ) fs }
: W { H h i n }

@ add inout H h ( Slice f ) s → v { ( vec_push [( Slice f )] . h fs s ) }

@ main → i {
    : ~ ( Vec f ) v ( vec_zeroed [f] 8 )
    : ~ W w @ W { @ H { ( vec_new [( Slice f )] ) } 0 }
    ( add . w h ( slice_from_vec [f] v ) )
    ( vec_clear [f] v )
    ^ ( slice_len [f] ( vec_at [( Slice f )] . . w h fs 0 ) )
}
