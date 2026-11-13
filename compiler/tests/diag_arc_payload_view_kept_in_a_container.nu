// diag_arc_payload_view_kept_in_a_container.nu — a view of an Arc's
// payload kept in a container is still one when it is read back out
// (Agora #682). An Arc's payload is frozen once made: every thread holding
// a clone reads it without a lock, so a change through a view of it races
// them, and replacing an element that owns memory frees it under them.
// Bound directly, the view was refused; pushed into a Vec, put in a map, in
// a struct a Vec holds, in a struct's field given it after the struct was
// built, or in a struct a helper builds, the view read back out was taken
// for one of nothing, and `slice_put` through it compiled. Each function
// below is refused with the frozen-payload message.
$ `stdlib/std/arc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: Win { ( Slice ( Vec i ) ) w i tag }

: Wins { ( Vec Win ) ws ( Arc ( Vec ( Vec i ) ) ) a }

@ fresh i k → ( Vec i ) {
    : ( Vec i ) r ( vec_new [i] )
    ( vec_push [i] r k )
    ^ r
}

// Pushed into a Vec, matched back out of it.
@ in_a_vec ( Arc ( Vec ( Vec i ) ) ) mine → v {
    : ( Vec ( Slice ( Vec i ) ) ) ws ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] ws ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) )
    ?? ( vec_get [( Slice ( Vec i ) )] ws 0 ) { T w → { ( slice_put [( Vec i )] w 0 ( fresh 1 ) ) } F → {} }
}

// …read back with vec_at, in place.
@ read_in_place ( Arc ( Vec ( Vec i ) ) ) mine → v {
    : ( Vec ( Slice ( Vec i ) ) ) ws ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] ws ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) )
    ( slice_put [( Vec i )] ( vec_at [( Slice ( Vec i ) )] ws 0 ) 0 ( fresh 2 ) )
}

// …bound from vec_at.
@ bound_from_it ( Arc ( Vec ( Vec i ) ) ) mine → v {
    : ( Vec ( Slice ( Vec i ) ) ) ws ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] ws ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) )
    : ( Slice ( Vec i ) ) w ( vec_at [( Slice ( Vec i ) )] ws 0 )
    ( slice_put [( Vec i )] w 0 ( fresh 3 ) )
}

// …handed back by a helper.
@ firstw ( Vec ( Slice ( Vec i ) ) ) ws → ( Slice ( Vec i ) ) { ^ ( vec_at [( Slice ( Vec i ) )] ws 0 ) }

@ through_a_helper ( Arc ( Vec ( Vec i ) ) ) mine → v {
    : ( Vec ( Slice ( Vec i ) ) ) ws ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] ws ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) )
    ( slice_put [( Vec i )] ( firstw ws ) 0 ( fresh 4 ) )
}

// In a struct a Vec holds.
@ in_a_vec_of_structs ( Arc ( Vec ( Vec i ) ) ) mine → v {
    : ( Vec Win ) ws ( vec_new [Win] )
    ( vec_push [Win] ws @ Win { ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) 0 } )
    ?? ( vec_get [Win] ws 0 ) { T x → { ( slice_put [( Vec i )] . x w 0 ( fresh 5 ) ) } F → {} }
}

// A map's value.
@ in_a_map ( Arc ( Vec ( Vec i ) ) ) mine → v {
    : ( @ i i ) hs \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) es \ i a i b → b { ^ ( eq_int a b ) }
    : ( HashMap i ( Slice ( Vec i ) ) ) m ( map_new [i ( Slice ( Vec i ) )] )
    : ?( Slice ( Vec i ) ) old ( map_set [i ( Slice ( Vec i ) )] m 1 ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) hs es )
    ?? ( map_get [i ( Slice ( Vec i ) )] m 1 hs es ) { T w → { ( slice_put [( Vec i )] w 0 ( fresh 6 ) ) } F → {} }
}

// A struct's field given one after the struct was built.
@ in_a_field_given_it ( Arc ( Vec ( Vec i ) ) ) mine ( Vec ( Vec i ) ) own → v {
    : ~ Win x @ Win { ( slice_from_vec [( Vec i )] own ) 0 }
    = . x w ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) )
    ( slice_put [( Vec i )] . x w 0 ( fresh 7 ) )
}

// A struct a helper builds over its Arc, read through an accessor.
@ mkwins ( Arc ( Vec ( Vec i ) ) ) h → Wins {
    : ( Vec Win ) ws ( vec_new [Win] )
    ( vec_push [Win] ws @ Win { ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] h ) ) 0 } )
    ^ @ Wins { ws ( arc_clone [( Vec ( Vec i ) )] h ) }
}

@ winof Wins x i k → ?Win { ^ ( vec_get [Win] . x ws k ) }

@ built_by_a_helper ( Arc ( Vec ( Vec i ) ) ) mine → v {
    : Wins x ( mkwins mine )
    ?? ( winof x 0 ) { T w → { ( slice_put [( Vec i )] . w w 0 ( fresh 8 ) ) } F → {} }
}

@ main → i {
    ^ 0
}
