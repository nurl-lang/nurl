// drop_element_of_an_arc_payload_changed_through_a_helper_is_refused: `( vg . ( arc_get [App] mine ) rs 3 )`, `vg` growing a Vec field of a `% Drop` element of the Arc payload
// Closed: agora #692, the frozen-Arc rule sees the change.
// main f9102b40: accepted (eight threads doing it: a double free).
// map: §6.5 | A3 | rejected | - | agora #692: a helper changing a % Drop element of an Arc payload is refused by the frozen-Arc rule
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
    ( vg . ( arc_get [App] mine ) rs 3 )
    ^ 0
}
