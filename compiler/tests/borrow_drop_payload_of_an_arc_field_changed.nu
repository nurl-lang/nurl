// borrow_drop_payload_of_an_arc_field_changed.nu — `?? ( vec_get [R] .
// ( arc_get [App] mine ) rs 0 ) { T e → { ( rg e k ) } … }`, R a struct
// with its own `% Drop` and a Vec field that `rg` grows: the payload is a
// view of the Arc's payload, so the frozen-Arc rule refuses the change, in
// place and in a closure, as for R without the Drop (Agora #763). The
// payload was lent from the bindings the scrutinee reads, and a field of
// a call's result is none of them.
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: R { ( Vec i ) v i n }

% Drop R { @ drop R r → v {} }

: App { ( Vec R ) rs i n }

@ mkr → R { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 7 ) ^ @ R { v 1 } }

@ rg R r i k → v { ( vec_push [i] . r v k ) }

@ mkapp → ( Arc App ) { : ( Vec R ) rs ( vec_new [R] ) ( vec_push [R] rs ( mkr ) ) ^ ( arc_new [App] @ App { rs 0 } ) }

@ viaclosure ( Arc App ) mine → v {
    : ( @ v i ) f \ i k → v { ?? ( vec_get [R] . ( arc_get [App] mine ) rs 0 ) { T e → { ( rg e k ) } F → {} } }
    ( f 3 )
}

@ main → i {
    : ( Arc App ) mine ( mkapp )
    ?? ( vec_get [R] . ( arc_get [App] mine ) rs 0 ) { T e → { ( rg e 3 ) } F → {} }
    ( viaclosure ( arc_clone [App] mine ) )
    ^ 0
}
