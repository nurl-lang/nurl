// closure_shared_through_a_wrapper_that_hands_its_parameter_to_arc_new: a closure handed to a function that puts its parameter into an Arc (bare and inside a literal) pushes to its capture
// AGORA-869 (fpA-r8): the ownership engine's rule for it; the walk's verdict is the same.
// map: §6.5 | A3 | rejected | - | a closure handed to a function that puts its parameter into an Arc (bare and inside a literal) pushes to its capture
$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: Holder { ( @ v i ) f i tag }

@ mk ( @ v i ) f → ( Arc Holder ) { ^ ( arc_new [Holder] @ Holder { f 7 } ) }

@ mk2 ( @ v i ) f → ( Arc ( @ v i ) ) { ^ ( arc_new [( @ v i )] f ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    : ( @ v i ) work \ i k → v { ( vec_push [i] xs k ) }
    : ( Arc Holder ) shared ( mk work )
    : ( Vec i ) ys ( vec_new [i] )
    : ( @ v i ) work2 \ i k → v { ( vec_push [i] ys k ) }
    : ( Arc ( @ v i ) ) s2 ( mk2 work2 )
    ^ 0
}
