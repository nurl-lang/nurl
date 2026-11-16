// cursor_repointed_at_a_parameter_field_then_grown_the_payload_an_arc_shares: `: ~ ( Vec i ) c ( vec_new )  = c . x v  push c` with x what arc_get lent: the cursor borrows the field, so the push grows the payload an Arc shares
// AGORA-869 (fpA-r8): the ownership engine's rule for it; the walk's verdict is the same.
// map: §6.5 | A3 | rejected | - | `: ~ ( Vec i ) c ( vec_new )  = c . x v  push c` with x what arc_get lent: the cursor borrows the field, so the push grows the payload an Arc shares
$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ g App x → v { : ~ ( Vec i ) c ( vec_new [i] ) = c . x v ( vec_push [i] c 1 ) }

@ h App x → v { ( vec_push [i] . x v 1 ) }

@ main → i {
    : ( Arc App ) shared ( arc_new [App] @ App { ( vec_new [i] ) 1 } )
    ( g ( arc_get [App] shared ) )
    ( h ( arc_get [App] shared ) )
    ^ 0
}
