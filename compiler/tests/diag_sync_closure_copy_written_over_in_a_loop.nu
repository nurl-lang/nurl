// diag_sync_closure_copy_written_over_in_a_loop.nu — a local that held a
// copy and is then given the capture's own handle is the capture from
// there on (docs/MEMORY.md §6.5; agora #639). `c` starts as a copy of the
// captured Vec, which the closure may grow; `= c ( vof app )` makes it
// the captured Vec itself, and the loop's next round grows that. A
// closure whose body writes over such a local is judged as if every call
// it made handed back what it was given. Without the assignment the
// closure is accepted (thread_sync_copy_made_by_a_callee.nu).

$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ main → i {
    : App app @ App { ( vec_new [i] ) 1 }
    : ( @ v i ) work \ i k → v {
        : ~ ( Vec i ) c ( vec_clone [i] . app v )
        : ~ i j 0
        ~ < j 3 {
            ( vec_push [i] c j )
            = c ( vof app )
            = j + j 1
        }
    }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    ^ 0
}

@ vof App x → ( Vec i ) { ^ . x v }
