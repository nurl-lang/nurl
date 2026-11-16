// closure_in_a_struct_literal_kept_in_an_arc_grows_its_env: a closure stored into a struct literal an Arc keeps pushes to its capture: the literal copies the env in, and every thread runs it on that one env
// AGORA-869 (fpA-r8): the ownership engine's rule for it; the walk's verdict is the same.
// map: §6.5 | A3 | rejected | - | a closure stored into a struct literal an Arc keeps pushes to its capture: the literal copies the env in, and every thread runs it on that one env
$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: Holder { ( @ v i ) f i tag }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    : ( @ v i ) work \ i k → v { ( vec_push [i] xs k ) }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    ^ 0
}
