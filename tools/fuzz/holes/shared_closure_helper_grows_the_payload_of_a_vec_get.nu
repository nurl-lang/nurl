// shared_closure_helper_grows_the_payload_of_a_vec_get: a thread-shared closure hands its captured struct to a function that matches `( vec_get … . a rows 0 )` and pushes to the payload. The closure sits in a struct in an Arc that eight threads run it out of, so every one of them grows the one buffer at once.
// The payload binding of a `??` over a call that lends out of a parameter is a handle read out of that parameter, like an element or a bound field.
// main (before agora #646): ASan double free — realloc of one buffer from several threads.
// map: §6.5 | A3 | rejected | - | a thread-shared closure's helper pushes to the payload `p` of `?? ( vec_get … . a rows 0 ) { T p → … }`: a change of the capture (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) log ( Vec ( Vec i ) ) rows ? ( Vec i ) extra ( Channel i ) jobs }

@ mkapp → App {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] rows ( vec_new [i] ) )
    ^ @ App { ( vec_new [i] ) rows @ ?( Vec i ) { T ( vec_new [i] ) } ( chan_new [i] ) }
}

@ grow App a i k → v { ?? ( vec_get [( Vec i )] . a rows 0 ) { T p → { ( vec_push [i] p k ) } F → {} } }

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
        ( grow app k )
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
