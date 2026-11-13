// arc_payload_changed_by_a_closure_value_called_on_it_is_refused: a closure value that pushes into its App parameter, called on the Arc's payload by 8 threads
// Closed: agora #657, a closure value called is a call of its node: the frozen-payload rule asks the node's summary, as it asks a named function's.
// main ff75baea: accepted (8 threads grow one Vec with no lock; ASan: attempting double-free on 6 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #657: a closure value called on the payload
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ reader ( Arc App ) mine i n → v {
    : ( @ v App ) g \ App y → v { ( vec_push [i] . y v 1 ) }
    : ~ i k 0
    ~ < k n { ( g ( arc_get [App] mine ) ) = k + k 1 }
}

@ main → i {
    : ( Arc App ) a ( arc_new [App] @ App { ( vec_new [i] ) 0 } )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i j 0
    ~ < j 8 {
        : ( Arc App ) mine ( arc_clone [App] a )
        : !Thread ThreadErr r ( thread_spawn \ → v { ( reader mine 3000 ) } )
        ?? r { T t → { ( vec_push [Thread] ts t ) } F e → {} }
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    ( nurl_println_int ( vec_len [i] . ( arc_get [App] a ) v ) )
    ^ 0
}
