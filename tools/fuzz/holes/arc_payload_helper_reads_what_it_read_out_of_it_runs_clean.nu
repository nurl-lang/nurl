// arc_payload_helper_reads_what_it_read_out_of_it_runs_clean: a function handed an Arc's payload binds an element, takes an accessor's lend and matches an option field of it — and only reads them — and sends on the payload's Channel, on eight threads. A frozen payload is read freely, and the send is the Channel's own (agora #639).
// The control for the arc_payload_helper_grows_* probes and arc_payload_reader_grows_the_payload_of_an_option_field.
// map: ThruOK.noShare | A3 | runs-clean | - | a function handed `( arc_get a )` binds an element, an accessor's lend and an option payload of it, reads their lengths and sends on the Channel beside them: no change of a frozen payload (agora #646)
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

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( note ( arc_get [App] mine ) k )
        : ( Vec i ) e ( vec_at [( Vec i )] . ( arc_get [App] mine ) rows 0 )
        ?? . ( arc_get [App] mine ) extra { T p → { : i both + ( vec_len [i] p ) ( vec_len [i] e ) } F → {} }
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc App ) mine ( arc_clone [App] shared )
        : ( @ v ) body \ → v { ( reader mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    : ~ i got 0
    : ~ b more T
    ~ more { ?? ( chan_try_recv [i] . ( arc_get [App] shared ) jobs ) { T x → { = got + got 1 } F → { = more F } } }
    ^ ? == got 24000 0 1
}
