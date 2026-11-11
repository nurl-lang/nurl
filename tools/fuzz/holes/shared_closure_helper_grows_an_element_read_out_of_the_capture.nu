// shared_closure_helper_grows_an_element_read_out_of_the_capture: a thread-shared closure hands its captured struct to a function that pushes to an element of the struct's Vec of Vecs, read with `vec_at` in the call itself. The closure sits in a struct in an Arc that eight threads run it out of, so every one of them grows the one buffer at once.
// The function's summary named no change of its parameter: the element handle is a copy, and the change made through it was recorded against the handle only. The thread rules now count a change through a handle read out of a parameter as a change of that parameter.
// main (before agora #646): ASan double free — realloc of one buffer from several threads.
// map: §6.5 | A3 | rejected | - | a thread-shared closure's helper pushes to `( vec_at … . a rows 0 )`, an element read out of its parameter: a change of the capture (agora #646)
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

@ grow App a i k → v { ( vec_push [i] ( vec_at [( Vec i )] . a rows 0 ) k ) }

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
