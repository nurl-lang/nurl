// drop_element_payload_of_an_arc_field_changed_in_place_is_refused: `?? ( vec_get [R] . ( arc_get [App] mine ) rs 0 ) { T e → { ( rg e 3 ) } … }`, R with its own `% Drop`, `rg` growing its Vec field
// Closed: agora #763, the payload is lent from what the scrutinee's call lends from, not only from the bindings it reads.
// main 46338880: accepted.
// map: §6.5 | A3 | rejected | - | agora #763: a ?? payload of a % Drop element of an Arc payload's field, changed in place, is refused by the frozen-Arc rule
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: R { ( Vec i ) v i n }

% Drop R { @ drop R r → v {} }

: App { ( Vec R ) rs i n }

@ mkr → R { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 7 ) ^ @ R { v 1 } }

@ rg R r i k → v { ( vec_push [i] . r v k ) }

@ vg ( Vec R ) rs i k → v { ( rg ( vec_at [R] rs 0 ) k ) }

@ ag App x i k → v { ( rg ( vec_at [R] . x rs 0 ) k ) }

@ mkapp → ( Arc App ) { : ( Vec R ) rs ( vec_new [R] ) ( vec_push [R] rs ( mkr ) ) ^ ( arc_new [App] @ App { rs 0 } ) }

@ main → i {
    : ( Arc App ) mine ( mkapp )
    ?? ( vec_get [R] . ( arc_get [App] mine ) rs 0 ) { T e → { ( rg e 3 ) } F → {} }
    ^ 0
}
