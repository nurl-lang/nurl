// not_sync_instance_of_a_sync_marked_generic_shared_through_a_forwarder: as own_sync_marked_generic_changed_through_a_generic_function_behind_a_forwarder_runs_clean, but the wrapper holds a bare Vec and the program takes its promise back for the one instance in use: `unsafe % Sync W { }` and `% NotSync ( W i ) { }`. The closure's forwarder hands the `( W i )` field to `wpush [i]`, which pushes with no lock. The closure sits in a struct in an Arc that eight threads run it out of, so every one of them grows the one buffer at once.
// Guard of #639's rule: a change through a by-value parameter is excused by the type the function instance was compiled with, and `( W i )` is not one that synchronises itself — the struct holding it may not even be reached from two threads.
// map: §6.5 | A3 | rejected | - | a thread-shared closure's forwarder hands its capture's `( W i )` field to a generic function that pushes to its Vec, `W` marked `unsafe % Sync` but `% NotSync ( W i )`: the instance is not excused (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: W [A] { ( Vec A ) v }

unsafe % Sync W {}

% NotSync ( W i ) {}

@ wpush [A] ( W A ) w A x → v { ( vec_push [A] . w v x ) }

: App { ( W i ) w i n }

@ mkapp → App { ^ @ App { @ ( W i ) { ( vec_new [i] ) } 1 } }

@ fwd App a i k → v { ( wpush [i] . a w k ) }

: Holder { ( @ v i ) f i tag }

@ hit ( Arc Holder ) a i n → v {
    : Holder h ( arc_get [Holder] a )
    : ( @ v i ) g . h f
    : ~ i j 0
    ~ < j n {
        ( g j )
        = j + j 1
    }
}

@ main → i {
    : App app ( mkapp )
    : ( @ v i ) work \ i k → v {
        ( fwd app k )
    }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        : ( @ v ) body \ → v { ( hit mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}
