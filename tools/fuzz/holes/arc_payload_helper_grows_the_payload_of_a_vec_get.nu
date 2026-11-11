// arc_payload_helper_grows_the_payload_of_a_vec_get: a function handed an Arc's payload matches `( vec_get … . a rows 0 )` and pushes to what it holds. Eight threads hold a clone of the Arc and read its payload with no lock, so every one of them grows the one buffer at once.
// The `??` payload binding is a handle read out of the function's parameter, which is the Arc's payload.
// main (before agora #646): ASan double free — realloc of one buffer from several threads.
// map: ThruOK.noShare | A3 | rejected | - | a function handed `( arc_get a )` pushes to the payload `p` of `?? ( vec_get … . a rows 0 ) { T p → … }`: a change of a frozen payload (agora #646)
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
