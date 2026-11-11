// diag_sync_closure_copy_refilled_through_inout.nu — a local that held a
// copy and is handed to an `inout` parameter may come back holding the
// capture's own handle (docs/MEMORY.md §6.5; agora #639). `c` starts as
// a copy of the captured Vec; `refill` may give it any value it can
// reach, the captured struct's Vec among them, and the loop's next round
// grows what `c` holds then. As with a plain assignment
// (diag_sync_closure_copy_written_over_in_a_loop.nu) the closure is
// judged as if every call it made handed back what it was given.

$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ refill inout ( Vec i ) dst App x → v { = dst ( vec_clone [i] . x v ) }

@ main → i {
    : App app @ App { ( vec_new [i] ) 1 }
    : ( @ v i ) work \ i k → v {
        : ~ ( Vec i ) c ( vec_clone [i] . app v )
        : ~ i j 0
        ~ < j 3 {
            ( vec_push [i] c j )
            ( refill c app )
            = j + j 1
        }
    }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    ^ 0
}
