// arcweak_of_an_arcweak_upgraded_on_two_threads_runs_clean: an `( ArcWeak ( ArcWeak i ) )` is captured by a `thread_spawn` closure; both threads upgrade the outer weak handle, then the inner one, and read the number. Every count involved is an Arc's atomic one and the payload is a number nobody changes.
// The control for arcweak_of_an_arcweak_of_a_share_handle_upgraded_and_changed_on_another_thread.
// map: §6.5 | A3 | runs-clean | - | guard: `( ArcWeak ( ArcWeak i ) )` captured by a spawned closure and upgraded twice on both threads: an ArcWeak held to Sync is its Arc, whose payload is asked in turn (agora #690)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/option.nu`

@ churn ( ArcWeak ( ArcWeak i ) ) ww i n → i {
    : ~ i k 0
    : ~ i sum 0
    ~ < k n {
        ?? ( arc_weak_upgrade [( ArcWeak i )] ww ) {
            T outer → {
                ?? ( arc_weak_upgrade [i] ( arc_get [( ArcWeak i )] outer ) ) {
                    T inner → { = sum + sum ( arc_get [i] inner ) }
                    F → {}
                }
            }
            F → {}
        }
        = k + k 1
    }
    ^ sum
}

@ main → i {
    : ( Arc i ) a ( arc_new [i] 5 )
    : ( Arc ( ArcWeak i ) ) holder ( arc_new [( ArcWeak i )] ( arc_downgrade [i] a ) )
    : ( ArcWeak ( ArcWeak i ) ) w1 ( arc_downgrade [( ArcWeak i )] holder )
    : ( ArcWeak ( ArcWeak i ) ) w2 ( arc_downgrade [( ArcWeak i )] holder )
    : ( Channel i ) out ( chan_new [i] )
    : ~ i here 0
    ?? ( thread_spawn \ → v { : b told ( chan_send [i] out ( churn w2 20000 ) ) } ) {
        T t → {
            = here ( churn w1 20000 )
            ( thread_join t )
        }
        F _ → {}
    }
    ?? ( chan_recv [i] out ) {
        T there → { ^ - + here there 200000 }
        F → {}
    }
    ^ 9
}
