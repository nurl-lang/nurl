// cursor_repointed_at_a_parameter_field_on_one_path_or_round_then_grown: the same, the repoint in one arm of a ?, or in an earlier round of a loop: the cursor may borrow the field
// AGORA-869 (fpA-r8): the ownership engine's rule for it; the walk's verdict is the same.
// map: §6.5 | A3 | rejected | - | the same, the repoint in one arm of a ?, or in an earlier round of a loop: the cursor may borrow the field
$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ g App x b k → v { : ~ ( Vec i ) c ( vec_new [i] ) ? k { = c . x v } {} ( vec_push [i] c 1 ) }

@ w App x → v { : ~ ( Vec i ) c ( vec_new [i] ) : ~ i j 0 ~ < j 3 { ( vec_push [i] c j ) = c . x v = j + j 1 } }

@ main → i {
    : ( Arc App ) shared ( arc_new [App] @ App { ( vec_new [i] ) 1 } )
    ( g ( arc_get [App] shared ) T )
    ( w ( arc_get [App] shared ) )
    ^ 0
}
