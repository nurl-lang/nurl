// drop_element_of_an_arc_payload_struct_changed_by_a_helper_is_refused: `( ag ( arc_get [App] mine ) 3 )`, `ag` growing a Vec field of a `% Drop` element of its App parameter
// Closed: agora #692.
// main f9102b40: accepted (eight threads doing it: a double free).
// map: §6.5 | A3 | rejected | - | agora #692: a helper changing a % Drop element of an Arc payload struct is refused
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
    ( ag ( arc_get [App] mine ) 3 )
    ^ 0
}
