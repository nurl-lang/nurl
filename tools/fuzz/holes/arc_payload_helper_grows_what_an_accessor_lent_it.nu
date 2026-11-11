// arc_payload_helper_grows_what_an_accessor_lent_it: a function handed an Arc's payload pushes to what an accessor (`@ logof App a → ( Vec i ) { ^ . a log }`) lends out of it. Eight threads hold a clone of the Arc and read its payload with no lock, so every one of them grows the one buffer at once.
// The push was recorded against the accessor's result, never against the payload the result was lent out of.
// main (before agora #646): ASan double free — realloc of one buffer from several threads.
// map: ThruOK.noShare | A3 | rejected | - | a function handed `( arc_get a )` pushes to `( logof a )`, an accessor's lend of the payload's Vec field: a change of a frozen payload (agora #646)
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

@ grow App a i k → v { ( vec_push [i] ( logof a ) k ) }

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( grow ( arc_get [App] mine ) k )
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
    ^ 0
}
