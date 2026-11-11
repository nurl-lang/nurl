// own_sync_marked_generic_changed_through_a_generic_function_behind_a_forwarder_runs_clean: a closure eight threads run out of a struct in an Arc hands its captured struct to a plain function that hands the struct's `( W i )` field on to the generic `wpush [A]`, which pushes to the Vec inside under the wrapper's own Mutex and answers the new length. `W [A]` carries the program's own `unsafe % Sync W { }` (true here: every change of the Vec is made under the lock), so the change `wpush` makes through its by-value `( W A )` parameter is the wrapper's own — judged by the instance `wpush [i]` was compiled with — and no change of the struct the forwarder read it out of (agora #639 — refused before it as "the closure changes 'app'"). The longest length a thread saw is 24000: all eight grew the one Vec, and no push was lost.
// The control for not_sync_instance_of_a_sync_marked_generic_shared_through_a_forwarder.
// map: §6.5 | A3 | runs-clean | - | a thread-shared closure's forwarder hands its capture's `( W i )` field to a generic function that changes it, `W` marked `unsafe % Sync` by the program and locking itself: the change is the instance's own (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: W [A] { Mutex m ( Vec A ) v }

unsafe % Sync W {}

@ wpush [A] ( W A ) w A x → i {
    ( mutex_lock . w m )
    ( vec_push [A] . w v x )
    : i n ( vec_len [A] . w v )
    ( mutex_unlock . w m )
    ^ n
}

: App { ( W i ) w i n }

@ mkapp → App { ^ @ App { @ ( W i ) { ( mutex_new ) ( vec_new [i] ) } 1 } }

@ fwd App a i k → i { ^ ( wpush [i] . a w k ) }

: Holder { ( @ i i ) f i tag }

@ hit ( Arc Holder ) a i n → i {
    : Holder h ( arc_get [Holder] a )
    : ( @ i i ) g . h f
    : ~ i j 0
    : ~ i top 0
    ~ < j n {
        : i len ( g j )
        ? > len top { = top len } {}
        = j + j 1
    }
    ^ top
}

@ main → i {
    : App app ( mkapp )
    : ( @ i i ) work \ i k → i {
        ^ ( fwd app k )
    }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    : Atomic best ( atomic_new 0 )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        : ( @ v ) body \ → v { : i before ( atomic_max best ( hit mine 3000 ) ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ ? == ( atomic_load best ) 24000 0 1
}
