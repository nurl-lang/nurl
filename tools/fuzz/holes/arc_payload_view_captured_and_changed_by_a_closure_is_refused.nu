// arc_payload_view_captured_and_changed_by_a_closure_is_refused: a closure that captured a bound view of the Arc's payload and pushes into it, run by 8 threads
// Closed: agora #657, what a closure run here does to a capture is the frozen-payload rule's, as the body's call written here would be.
// main ff75baea: accepted (8 threads grow one Vec with no lock; ASan: attempting double-free on 6 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #657: a closure changing a captured payload view
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ reader ( Arc App ) mine i n → v {
    : App p ( arc_get [App] mine )
    : ( @ v ) c \ → v { ( vec_push [i] . p v 1 ) }
    : ~ i k 0
    ~ < k n { ( c ) = k + k 1 }
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
