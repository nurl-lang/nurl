// diag_sync_closure_callee_below_lends_its_argument.nu — a function
// defined below the closure that calls it is judged by the summary it
// ends with (docs/MEMORY.md §6.5; agora #639, #646). `same` hands its
// parameter back: what the closure grows is the payload of the captured
// struct's option, the buffer every thread running the closure reaches.
// A callee that hands back a copy leaves the closure free to change it
// (thread_sync_copy_made_by_a_callee.nu).

$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: App { ? ( Vec i ) ov i n }

@ main → i {
    : App app @ App { @ ?( Vec i ) { T ( vec_new [i] ) } 1 }
    : ( @ v i ) work \ i k → v {
        ?? . app ov {
            T p → {
                : ( Vec i ) c ( same p )
                ( vec_push [i] c k )
            }
            F → {}
        }
    }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    ^ 0
}

@ same ( Vec i ) x → ( Vec i ) { ^ x }
