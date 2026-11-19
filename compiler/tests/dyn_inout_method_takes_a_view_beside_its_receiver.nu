// AGORA-927: a trait object's `inout` method may take parameters beside the
// receiver. The call hands the object's environment over to the method's code
// as its `inout` receiver and passes the extra arguments as they are; here a
// slice view of a Vec the object does not own. The formal model types this
// call (`StmtT.callcE` with `zs`, A2/EnvHand.lean): the arguments beside the
// receiver reach nothing of the environment, and the environment is handed
// back into the object after the call.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { ( Vec i ) items }

% Fill [T] {
    @ add inout T self ( Slice i ) s → i
}

% Fill Bag {
    @ add inout Bag b ( Slice i ) s → i {
        ( vec_push [i] . b items ( slice_at [i] s 0 ) )
        ^ ( vec_len [i] . b items )
    }
}

@ main → i {
    : ~ % Fill k ( dyn Fill @ Bag { ( vec_new [i] ) } )
    : ( Vec i ) src ( vec_new [i] )
    ( vec_push [i] src 5 )
    : ( Slice i ) s ( slice_from_vec [i] src )
    ( nurl_println_int ( add k s ) )
    ( nurl_println_int ( add k s ) )
    ( nurl_println_int ( slice_at [i] s 0 ) )
    ^ 0
}
