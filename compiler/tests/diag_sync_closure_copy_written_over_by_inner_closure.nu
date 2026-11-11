// diag_sync_closure_copy_written_over_by_inner_closure.nu — a closure
// run in the body may write over the body's local as well (docs/MEMORY.md
// §6.5; agora #639). `c` starts as a copy of the captured Vec; `again`
// captured `c` and gives it the captured Vec itself, so the loop's next
// round grows that. The assignment counts wherever it stands
// (diag_sync_closure_copy_written_over_in_a_loop.nu).

$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ main → i {
    : App app @ App { ( vec_new [i] ) 1 }
    : ( @ v i ) work \ i k → v {
        : ~ ( Vec i ) c ( vec_clone [i] . app v )
        : ( @ v ) again \ → v { = c . app v }
        : ~ i j 0
        ~ < j 3 {
            ( vec_push [i] c j )
            ( again )
            = j + j 1
        }
    }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    ^ 0
}
