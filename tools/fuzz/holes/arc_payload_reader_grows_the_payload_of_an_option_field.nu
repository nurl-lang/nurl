// arc_payload_reader_grows_the_payload_of_an_option_field: a thread matches the `?( Vec i )` field of an Arc's payload and pushes to what it holds. Eight threads hold a clone of the Arc and read its payload with no lock, so every one of them grows the one buffer at once.
// The `??` payload binding views the Arc's payload: a mutator handed it changes what every clone reads.
// main (before agora #646): ASan double free — realloc of one buffer from several threads.
// map: ThruOK.noShare | A3 | rejected | - | a thread pushes to the payload `p` of `?? . ( arc_get a ) extra { T p → … }`: a change of a frozen payload (agora #646)
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

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ?? . ( arc_get [App] mine ) extra { T p → { ( vec_push [i] p k ) } F → {} }
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
