// borrow_stored_owner_dropped.nu — a handle stored into an owner lives as
// long as the owner holds it. Reading it through its own name is fine
// until then (docs/MEMORY.md §2.12); two ways the owner lets go of it were
// not followed and read freed memory (`vec_len` of a 2-element Vec read 24):
//
//   * a handle field of the owner is assigned a new value — the old one,
//     maybe the stored handle, is dropped (which field holds which value
//     is not tracked, so the stored value is MAYBE-freed);
//   * a container a value was pushed into is released;
//   * a container call drops some of its elements, or hands one out to a
//     caller that may drop it (`vec_clear`, `vec_pop`, `map_set`, ...).
//
// CONTROLS: reading a stored value while its owner still holds it; a
// field assignment of a DIFFERENT struct; an element-dropping call on a
// DIFFERENT container.

$ `stdlib/core/vec.nu`

: Holder { ( Vec i ) v }

@ fieldset → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 5 ) ( vec_push [i] a 6 )
    : ~ Holder h @ Holder { a }
    = . h v ( vec_new [i] )
    ^ ( vec_len [i] a )
}

@ container → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 5 ) ( vec_push [i] a 6 )
    : ( Vec ( Vec i ) ) all ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] all a )
    ( vec_free [( Vec i )] all )
    ^ ( vec_len [i] a )
}

@ elem_clear → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 5 ) ( vec_push [i] a 6 )
    : ( Vec ( Vec i ) ) all ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] all a )
    ( vec_clear [( Vec i )] all )
    ^ ( vec_len [i] a )
}

@ elem_pop → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 5 ) ( vec_push [i] a 6 )
    : ( Vec ( Vec i ) ) all ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] all a )
    : ?( Vec i ) last ( vec_pop [( Vec i )] all )
    ^ ( vec_len [i] a )
}

@ controls → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 5 )
    : ~ Holder h @ Holder { a }
    : ~ Holder other @ Holder { ( vec_new [i] ) }
    = . other v ( vec_new [i] )
    : ( Vec ( Vec i ) ) all ( vec_new [( Vec i )] )
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [( Vec i )] all b )
    : ( Vec ( Vec i ) ) other_all ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] other_all ( vec_new [i] ) )
    ( vec_clear [( Vec i )] other_all )
    ^ + ( vec_len [i] a ) ( vec_len [i] b )
}

@ main → i {
    ^ + + + + ( fieldset ) ( container ) ( elem_clear ) ( elem_pop ) ( controls )
}
