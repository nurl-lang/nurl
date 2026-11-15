// arc_payload_view_bound_in_a_loop_captured_and_changed_by_a_closure_is_refused: as arc_payload_view_captured_and_changed_by_a_closure_is_refused, the payload view and the closure made afresh in every round of the loop (d03)
// Closed on main by 2026-11-15 (agora #834): a closure made in the loop over a payload view bound there is judged by the frozen-payload rule like one made above it.
// main 006aa3e8: accepted (8 threads grow one Vec with no lock; ASan: double free).
// map: §6.5 | A3 | rejected | - | agora #834: a closure changing a payload view bound in the same loop round
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: App { ( Vec i ) v i n }

@ mkapp → App {
    ^ @ App { ( vec_new [i] ) 1 }
}

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        : App p ( arc_get [App] mine )
        : ( @ v ) c \ → v { ( vec_push [i] . p v 1 ) }
        ( c )
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
