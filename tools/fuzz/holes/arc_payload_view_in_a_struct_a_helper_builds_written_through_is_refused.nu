// arc_payload_view_in_a_struct_a_helper_builds_written_through_is_refused: a helper builds a struct holding a Vec of payload views over its Arc parameter; an accessor hands one back, written through by two threads
// Closed: agora #682, an owner bound to a value holding a payload view holds one.
// main 07d73fb1: accepted (a data race on every run; ASan: attempting double-free on 2 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #682: a payload view in a struct a helper builds, read through an accessor, is one
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
: Wins { ( Vec Win ) ws ( Arc ( Vec ( Vec i ) ) ) a }

@ mkwins ( Arc ( Vec ( Vec i ) ) ) h → Wins {
    : ( Vec Win ) ws ( vec_new [Win] )
    ( vec_push [Win] ws @ Win { ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] h ) ) 0 } )
    ^ @ Wins { ws ( arc_clone [( Vec ( Vec i ) )] h ) }
}

@ winof Wins x i k → ?Win { ^ ( vec_get [Win] . x ws k ) }

@ writer ( Arc ( Vec ( Vec i ) ) ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        : Wins x ( mkwins mine )
        ?? ( winof x 0 ) { T w → { ( slice_put [( Vec i )] . w w 0 ( fresh k ) ) } F → {} }
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
