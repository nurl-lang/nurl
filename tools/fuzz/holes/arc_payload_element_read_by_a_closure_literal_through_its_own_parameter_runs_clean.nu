// arc_payload_element_read_by_a_closure_literal_through_its_own_parameter_runs_clean: guard of …_grown_by_a_closure_literal_…: the same closure only reads the element, on 8 threads
// Guard (agora #834): a closure literal that only reads what its parameter lends stays accepted.
// main: runs clean.
// map: §6.5 | A3 | runs-clean | - | agora #834 guard: a closure literal reading an element lent out of its own parameter
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
        : ( @ v App ) g \ App y → v { : i _l ( vec_len [i] ( vec_at [( Vec i )] . y vv 0 ) ) }
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
