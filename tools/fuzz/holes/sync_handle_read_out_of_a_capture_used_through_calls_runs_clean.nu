// sync_handle_read_out_of_a_capture_used_through_calls_runs_clean: a closure four threads run hands its captured struct on, two calls deep, to a function that sends on the struct's Channel, on a Channel inside its Vec of them, and counts in its Atomic. Each change is made through a handle that synchronises itself, borrowed by value: it is the handle's own, wherever the handle was read out of (agora #639 — refused before it as "the closure changes 'app'").
// The control for sync_handle_helper_grows_the_plain_field_beside_it_on_two_threads.
// map: §6.5 | A3 | runs-clean | - | a thread-shared closure's helpers send on its captured struct's Channel field, on an element of its Vec of Channels and bump its Atomic, two calls deep: changes made through self-synchronising handles borrowed by value (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs Atomic hits ( Vec ( Channel i ) ) lanes i n }

@ note App a i k → v {
    : b sent ( chan_send [i] . a jobs k )
    : b laned ( chan_send [i] ( vec_at [( Channel i )] . a lanes 0 ) k )
    : i before ( atomic_add . a hits 1 )
}

@ deep App a i k → v { ( note a k ) }

@ drain ( Channel i ) ch → i {
    : ~ i n 0
    : ~ b more T
    ~ more { ?? ( chan_try_recv [i] ch ) { T x → { = n + n 1 } F → { = more F } } }
    ^ n
}

@ main → i {
    : ( Vec ( Channel i ) ) lanes ( vec_new [( Channel i )] )
    ( vec_push [( Channel i )] lanes ( chan_new [i] ) )
    : App app @ App { ( chan_new [i] ) ( atomic_new 0 ) lanes 1 }
    : ( @ v i ) work \ i k → v { ( deep app k ) }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : ( Arc ( @ v i ) ) mine ( arc_clone [( @ v i )] shared )
        : ( @ v ) body \ → v {
            : ~ i j 0
            ~ < j 2000 {
                : ( @ v i ) run ( arc_get [( @ v i )] mine )
                ( run j )
                = j + j 1
            }
        }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    : i got + ( drain . app jobs ) ( drain ( vec_at [( Channel i )] . app lanes 0 ) )
    ^ ? & == got 16000 == ( atomic_load . app hits ) 8000 0 1
}
