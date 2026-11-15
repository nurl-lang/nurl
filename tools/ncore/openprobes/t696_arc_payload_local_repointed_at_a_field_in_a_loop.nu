// map: §6.5 | A3 | rejected | - | agora #696: a function handed `( arc_get a )` pushes to a local, then `= c . x v` in the loop: eight threads grow the frozen payload's Vec
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ work App x i k → i {
    : ~ ( Vec i ) c ( vec_new [i] )
    : ~ i j 0
    ~ < j 4000 { ( vec_push [i] c j ) = c . x v = j + j 1 }
    ^ k
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] @ App { ( vec_new [i] ) 1 } )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc App ) mine ( arc_clone [App] shared )
        : ( @ v ) body \ → v {
            : ~ i r 0
            ~ < r 4 { : i z ( work ( arc_get [App] mine ) r ) = r + r 1 }
        }
        ?? ( thread_spawn body ) { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}
