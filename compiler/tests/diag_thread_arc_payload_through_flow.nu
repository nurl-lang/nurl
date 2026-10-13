// An Arc's payload is frozen once made (docs/MEMORY.md §6.5), and the
// rule is decided on the borrow walk, not on how the view is spelled:
// what a call lends through an Arc parameter is a view of the payload,
// followed into either arm of a `?`, a match payload, an element an
// accessor lends, a name the view is copied to, a field of a call's
// result and a helper that hands its argument back. Each of these was
// accepted by a check that tracked arc_get bindings by name.
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: Box2 { ( Vec i ) xs }

@ id_vec ( Vec i ) v → ( Vec i ) { ^ v }

@ main → i {
    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] ( vec_new [i] ) )
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    : ( Arc ( Vec ( Vec i ) ) ) aa ( arc_new [( Vec ( Vec i ) )] vv )
    : ( Arc Box2 ) ba ( arc_new [Box2] @ Box2 { ( vec_new [i] ) } )
    : b c == 1 1
    // a `?` arm
    : ( Vec i ) v ? c ( arc_get [( Vec i )] a ) ( vec_new [i] )
    ( vec_push [i] v 1 )
    // a match payload
    ?? ( vec_get [( Vec i )] ( arc_get [( Vec ( Vec i ) )] aa ) 0 ) { T inner → { ( vec_push [i] inner 2 ) } F _ → {} }
    // an element an accessor lends, bound
    : ( Vec i ) e ( vec_at [( Vec i )] ( arc_get [( Vec ( Vec i ) )] aa ) 0 )
    ( vec_push [i] e 3 )
    // a name the view is copied to
    : ( Vec i ) w0 ( arc_get [( Vec i )] a )
    : ( Vec i ) w w0
    ( vec_push [i] w 4 )
    // a field of a call's result
    ( vec_push [i] . ( arc_get [Box2] ba ) xs 5 )
    // a helper that hands its argument back
    ( vec_push [i] ( id_vec ( arc_get [( Vec i )] a ) ) 6 )
    ^ 0
}
