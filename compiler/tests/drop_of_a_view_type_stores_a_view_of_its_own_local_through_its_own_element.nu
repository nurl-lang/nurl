// A `% Drop` of a struct that holds a slice, whose code stores a view of
// its own local `w` into `( vec_at loc 0 )` of another local it made (Agora
// #916): the store reaches only memory the destructor owns, and what it
// stores views only memory the destructor owns, so it changes nothing the
// slice the struct holds views. formal/A2 types such a store `edit false`
// (StmtT.editBV through a fresh borrow, storing a fresh, held-fresh view).
// view of its own local into `( vec_at loc 0 )` of another local it made.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: V { ( Slice i ) s i k }

% Drop V { @ drop V d → v {
        : ( Vec i ) w ( vec_new [i] )
        ( vec_push [i] w 9 )
        : ( Vec ( Vec ( Slice i ) ) ) loc ( vec_new [( Vec ( Slice i ) )] )
        ( vec_push [( Vec ( Slice i ) )] loc ( vec_new [( Slice i )] ) )
        ( vec_push [( Slice i )] ( vec_at [( Vec ( Slice i ) )] loc 0 ) ( slice_from_vec [i] w ) )
        ( nurl_println_int ( vec_len [( Slice i )] ( vec_at [( Vec ( Slice i ) )] loc 0 ) ) )
        ( nurl_println_int ( slice_at [i] . d s 0 ) )
    } }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    : k 3
    : x @ V { s k }
    ^ 0
}
