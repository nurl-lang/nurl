// The store of compiler/tests/drop_of_a_view_type_stores_a_view_of_its_own_local_through_its_own_element.nu, with the
// stored view's source ended before the view is read (Agora #916): 'loc'
// holds what was stored into its element, so reading it after 'w' ended is
// refused. The formal side records the same: the store adds what it stores
// to 'loc' (holdThru), as for every editBV.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: V { ( Slice i ) s i k }

% Drop V { @ drop V d → v {
        : ( Vec ( Vec ( Slice i ) ) ) loc ( vec_new [( Vec ( Slice i ) )] )
        ( vec_push [( Vec ( Slice i ) )] loc ( vec_new [( Slice i )] ) )
        {
            : ( Vec i ) w ( vec_new [i] )
            ( vec_push [i] w 9 )
            ( vec_push [( Slice i )] ( vec_at [( Vec ( Slice i ) )] loc 0 ) ( slice_from_vec [i] w ) )
        }
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
