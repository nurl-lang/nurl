// arc_payload_view_in_a_struct_in_a_vec_written_through_is_refused: a struct holding a Slice of an Arc's payload pushed into a local Vec, its field written through after vec_get, by two threads
// Closed: agora #682, the struct matched back out of the holder is a payload view.
// main 07d73fb1: accepted (a data race on every run; ASan: attempting double-free on 4 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #682: a payload view in a struct a Vec holds is still one
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

: Win { ( Slice ( Vec i ) ) w i tag }

@ writer ( Arc ( Vec ( Vec i ) ) ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Vec Win ) ws ( vec_new [Win] )
        ( vec_push [Win] ws @ Win { ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) 0 } )
        ?? ( vec_get [Win] ws 0 ) { T x → { ( slice_put [( Vec i )] . x w 0 ( fresh k ) ) } F → {} }
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
