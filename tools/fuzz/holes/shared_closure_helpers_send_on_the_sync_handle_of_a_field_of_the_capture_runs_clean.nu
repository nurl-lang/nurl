// shared_closure_helpers_send_on_the_sync_handle_of_a_field_of_the_capture_runs_clean: a closure eight threads run hands its captured struct on, two calls deep, to a function that sends on `. . a in c`: the Channel of the struct's inner struct. The change is made through the Channel, borrowed by value, a field of a field in: the handle's own (agora #639 — refused before it as "the closure changes 'app'"). Every send arrives.
// The control for shared_closure_helpers_grow_the_plain_field_of_a_field_beside_a_sync_handle.
// map: §6.5 | A3 | runs-clean | - | a thread-shared closure's helpers send on `. . a in c`, the Channel of a field of the capture, two calls deep: a change made through a self-synchronising handle read out of a field of a field (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Inner { ( Vec i ) v ( Channel i ) c }

: App { Inner in i n }

@ mkapp → App { ^ @ App { @ Inner { ( vec_new [i] ) ( chan_new [i] ) } 1 } }

@ second App a i k → v { : b sent ( chan_send [i] . . a in c k ) }

@ first App a i k → v { ( second a k ) }

@ drain ( Channel i ) ch → i {
    : ~ i n 0
    : ~ b more T
    ~ more { ?? ( chan_try_recv [i] ch ) { T x → { = n + n 1 } F → { = more F } } }
    ^ n
}

@ main → i {
    : App app ( mkapp )
    : ( @ v i ) work \ i k → v {
        ( first app k )
    }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc ( @ v i ) ) mine ( arc_clone [( @ v i )] shared )
        : ( @ v ) body \ → v {
            : ~ i j 0
            ~ < j 3000 {
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
    ^ ? == ( drain . . app in c ) 24000 0 1
}
