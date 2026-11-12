// arcweak_of_a_locked_vec_and_of_a_scalar_upgraded_on_another_thread_runs_clean: an `( ArcWeak ( Locked ( Vec i ) ) )` and an `( ArcWeak i )` are captured by a `thread_spawn` closure, upgraded there, and the Vec is grown under its lock: both payloads may be shared through an Arc, so their ArcWeak may cross.
// The control for arcweak_of_a_share_handle_upgraded_and_changed_on_another_thread.
// map: §6.5 | A3 | runs-clean | - | guard: `( ArcWeak ( Locked ( Vec i ) ) )` and `( ArcWeak i )` captured by a spawned closure and upgraded there: an ArcWeak of a Sync payload crosses (agora #690)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ( Arc ( Locked ( Vec i ) ) ) a ( arc_new [( Locked ( Vec i ) )] ( locked_new [( Vec i )] ( vec_new [i] ) ) )
    : ( ArcWeak ( Locked ( Vec i ) ) ) w ( arc_downgrade [( Locked ( Vec i ) )] a )
    : ( Arc i ) n ( arc_new [i] 7 )
    : ( ArcWeak i ) wn ( arc_downgrade [i] n )
    : ~ i got 0
    ?? ( thread_spawn \ → v {
        ?? ( arc_weak_upgrade [( Locked ( Vec i ) )] w ) {
            T up → { ( locked_update [( Vec i )] ( arc_get [( Locked ( Vec i ) )] up ) \ inout ( Vec i ) xs → v { ( vec_push [i] xs 1 ) } ) }
            F → {}
        }
        ?? ( arc_weak_upgrade [i] wn ) {
            T up → { : i x ( arc_get [i] up ) }
            F → {}
        }
    } ) {
        T t → { = got ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
