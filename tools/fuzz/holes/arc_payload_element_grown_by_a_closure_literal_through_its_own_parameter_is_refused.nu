// arc_payload_element_grown_by_a_closure_literal_through_its_own_parameter_is_refused: a closure literal pushing into an element LENT out of its own App parameter, called on the Arc's payload by 8 threads (c13)
// Closed on main by 2026-11-15 (agora #834): a change through a value lent out of a closure literal's own parameter is in the closure's summary, so the frozen-payload rule refuses the call.
// main 006aa3e8: accepted (8 threads grow one Vec with no lock; ASan: double free).
// map: §6.5 | A3 | rejected | - | agora #834: a closure literal growing an element lent out of its own parameter, called on the payload
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: App { ( Vec ( Vec i ) ) vv i n }

@ mkapp → App {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    ^ @ App { vv 1 }
}

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        : ( @ v App ) g \ App y → v { ( vec_push [i] ( vec_at [( Vec i )] . y vv 0 ) 1 ) }
        ( g ( arc_get [App] mine ) )
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc App ) mine ( arc_clone [App] shared )
        : ( @ v ) body \ → v { ( reader mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F e → { ( nurl_eprintln `spawn failed` ) }
        }
        = t + t 1
    }
    : ~ i q 0
    ~ < q ( vec_len [Thread] ts ) { : i joined ( thread_join ( vec_at [Thread] ts q ) ) = q + q 1 }
    ^ 0
}
