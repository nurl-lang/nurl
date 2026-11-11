// arc_payload_helper_grows_an_element_it_bound_to_a_name: a function handed an Arc's payload binds an element of the payload's Vec of Vecs to a name and pushes to it. Eight threads hold a clone of the Arc and read its payload with no lock, so every one of them grows the one buffer at once.
// The binding is a handle on the element's buffer; the push through it changed nothing the function's summary knew to be its parameter's.
// main (before agora #646): ASan double free — realloc of one buffer from several threads.
// map: ThruOK.noShare | A3 | rejected | - | a function handed `( arc_get a )` binds `: ( Vec i ) e ( vec_at … . a rows 0 )` and pushes to `e`: a change of a frozen payload (agora #646)
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

@ grow App a i k → v {
    : ( Vec i ) e ( vec_at [( Vec i )] . a rows 0 )
    ( vec_push [i] e k )
}

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
