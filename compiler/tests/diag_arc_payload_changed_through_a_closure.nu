// diag_arc_payload_changed_through_a_closure.nu — a change to an Arc's
// payload made by a closure is the frozen-payload rule's (Agora #657). An
// Arc's payload is frozen once made: every thread holding a clone reads it
// without a lock, so a change to it races them. A named function called on
// the payload, or the change written out in place, was refused. Called
// through a closure value, a closure parameter or a copy of one, or made
// in the body of a closure that captured a view of the payload — run here,
// by a function handed it, or by another closure — it compiled. Each
// function below is refused with the frozen-payload message.
$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

// A closure value called on the payload.
@ a_value ( Arc App ) mine → v {
    : ( @ v App ) g \ App y → v { ( vec_push [i] . y v 1 ) }
    ( g ( arc_get [App] mine ) )
}

// …a copy of one.
@ a_copy ( Arc App ) mine → v {
    : ( @ v App ) g \ App y → v { ( vec_push [i] . y v 1 ) }
    : ( @ v App ) g2 g
    ( g2 ( arc_get [App] mine ) )
}

// A closure parameter called on the payload, which its caller hands a
// literal that changes its argument.
@ apply ( @ v App ) g ( Arc App ) mine → v {
    ( g ( arc_get [App] mine ) )
}

@ a_parameter ( Arc App ) mine → v {
    ( apply \ App y → v { ( vec_push [i] . y v 1 ) } mine )
}

// A closure that captured a view of the payload and changes it.
@ a_capture ( Arc App ) mine → v {
    : App p ( arc_get [App] mine )
    : ( @ v ) c \ → v { ( vec_push [i] . p v 1 ) }
    ( c )
}

// …that hands it to a helper that changes it.
@ bump App y → v {
    ( vec_push [i] . y v 1 )
}

@ a_capture_to_a_helper ( Arc App ) mine → v {
    : App p ( arc_get [App] mine )
    : ( @ v ) c \ → v { ( bump p ) }
    ( c )
}

// …run by a function handed it.
@ run_it ( @ v ) f → v {
    ( f )
}

@ a_capture_run_by_a_function ( Arc App ) mine → v {
    : App p ( arc_get [App] mine )
    : ( @ v ) c \ → v { ( vec_push [i] . p v 1 ) }
    ( run_it c )
}

// …run by another closure.
@ a_capture_run_by_a_closure ( Arc App ) mine → v {
    : App p ( arc_get [App] mine )
    : ( @ v ) c \ → v { ( vec_push [i] . p v 1 ) }
    : ( @ v ) c2 \ → v { ( c ) }
    ( c2 )
}

@ main → i {
    ^ 0
}
