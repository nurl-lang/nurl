// AGORA-927: the refused twin of dyn_inout_method_takes_a_view_beside_its_receiver.
// `s` views `it`, which moved into the trait object's environment, so the
// view reaches the environment the method changes. The formal model refuses
// such an argument beside the receiver (`callcE_arg_views_pkg`): the call
// changes the object, and no other argument may reach it in memory.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { ( Vec i ) items }

% Fill [T] {
    @ add inout T self ( Slice i ) s → i
}

% Fill Bag {
    @ add inout Bag b ( Slice i ) s → i {
        ( vec_push [i] . b items 9 )
        ( vec_push [i] . b items 9 )
        ( vec_push [i] . b items 9 )
        ( vec_push [i] . b items 9 )
        ^ ( slice_at [i] s 0 )
    }
}

@ main → i {
    : ( Vec i ) it ( vec_new [i] )
    ( vec_push [i] it 5 )
    : ( Slice i ) s ( slice_from_vec [i] it )
    : ~ % Fill k ( dyn Fill @ Bag { it } )
    ( nurl_println_int ( add k s ) )
    ^ 0
}
