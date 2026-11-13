// arc_payload_view_handed_back_by_a_helper_written_through_is_refused: a helper hands back an element of a local Vec of payload views; written through in place, by two threads
// Closed: agora #682, what a helper lends out of a holder of payload views is one.
// main 07d73fb1: accepted (a data race on every run; ASan: attempting double-free on 4 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #682: a payload view a helper hands back out of a Vec is still one
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

@ fresh i k → ( Vec i ) {
    : ( Vec i ) r ( vec_new [i] )
    ( vec_push [i] r k )
    ^ r
}

@ firstw ( Vec ( Slice ( Vec i ) ) ) ws → ( Slice ( Vec i ) ) { ^ ( vec_at [( Slice ( Vec i ) )] ws 0 ) }

@ writer ( Arc ( Vec ( Vec i ) ) ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Slice ( Vec i ) ) ) ws ( vec_new [( Slice ( Vec i ) )] )
        ( vec_push [( Slice ( Vec i ) )] ws ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) )
        ( slice_put [( Vec i )] ( firstw ws ) 0 ( fresh k ) )
        = k + k 1
    }
}

@ main → i {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] rows ( fresh 0 ) )
    : ( Arc ( Vec ( Vec i ) ) ) shared ( arc_new [( Vec ( Vec i ) )] rows )
    : ( Arc ( Vec ( Vec i ) ) ) other ( arc_clone [( Vec ( Vec i ) )] shared )
    : ( @ v ) body \ → v { ( writer other 20000 ) }
    ?? ( thread_spawn body ) {
        T th → {
            ( writer shared 20000 )
            : i joined ( thread_join th )
        }
        F _ → {}
    }
    ^ 0
}
