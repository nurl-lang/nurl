// shared_closure_helper_reads_what_it_read_out_of_the_capture_runs_clean: a thread-shared closure hands its captured struct to a function that binds an element, takes an accessor's lend and matches an option field of it — and only reads them — and sends on the struct's Channel. Reading a handle read out of a parameter changes nothing, and the send is the Channel's own (agora #639).
// The control for the shared_closure_helper_grows_* probes and shared_closure_grows_the_payload_of_an_option_field: what is counted is a change through the handle, not the reading of it out.
// map: §6.5 | A3 | runs-clean | - | a thread-shared closure's helper binds an element, an accessor's lend and an option payload of its parameter, reads their lengths and sends on the Channel beside them: no change of the capture (agora #646)
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

@ logof App a → ( Vec i ) { ^ . a log }

@ look App a i k → i {
    : ( Vec i ) e ( vec_at [( Vec i )] . a rows 0 )
    : i seen + ( vec_len [i] e ) ( vec_len [i] ( logof a ) )
    ?? . a extra { T p → { ^ + seen ( vec_len [i] p ) } F → {} }
    ^ seen
}

@ note App a i k → v { : b sent ( chan_send [i] . a jobs ( look a k ) ) }

@ main → i {
    : App app ( mkapp )
    : ( @ v i ) work \ i k → v {
        ( note app k )
        : ( Vec i ) e ( vec_at [( Vec i )] . app rows 0 )
        ?? . app extra { T p → { : i both + ( vec_len [i] p ) ( vec_len [i] e ) } F → {} }
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
    : ~ i got 0
    : ~ b more T
    ~ more { ?? ( chan_try_recv [i] . app jobs ) { T x → { = got + got 1 } F → { = more F } } }
    ^ ? == got 24000 0 1
}
