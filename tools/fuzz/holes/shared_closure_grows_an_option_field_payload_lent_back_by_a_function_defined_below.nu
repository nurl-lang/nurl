// shared_closure_grows_an_option_field_payload_lent_back_by_a_function_defined_below: a thread-shared closure matches its captured struct's option field, hands the payload to `same` — DEFINED BELOW the closure, and handing its parameter back (`^ x`) — binds the result and pushes to the binding. The closure sits in a struct in an Arc that eight threads run it out of, so every one of them grows the one buffer at once.
// A function defined below the closure that calls it has no summary when the call is read; the binding is read out of the call's argument where the callee's FINAL summary lends it, so the push is a change of the capture.
// main (before agora #646): ASan heap-use-after-free / double free — realloc of one buffer from several threads.
// map: §6.5 | A3 | rejected | - | a thread-shared closure binds the result of a function defined below it, which hands its parameter back, over the payload of a `??` on a captured option field, and pushes to the binding: a change of the capture (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ? ( Vec i ) extra i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) @ ?( Vec i ) { T ( vec_new [i] ) } 1 } }

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
        ?? . app extra {
            T p → {
                : ( Vec i ) c ( same p )
                ( vec_push [i] c k )
            }
            F → {}
        }
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

@ same ( Vec i ) x → ( Vec i ) { ^ x }
