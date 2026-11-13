// arc_payload_view_in_a_field_assigned_later_written_through_is_refused: a struct's view field given a Slice of an Arc's payload after the struct was built, then written through, by two threads
// Closed: agora #682, a field store of a payload view makes the struct one, as its literal does.
// main 07d73fb1: accepted (a data race on every run; ASan: attempting double-free on 3 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #682: a struct given a payload view in a field after it was built is one
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
    : ( Vec ( Vec i ) ) mine_own ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] mine_own ( fresh 1 ) )
    : ~ i k 0
    ~ < k n {
        : ~ Win x @ Win { ( slice_from_vec [( Vec i )] mine_own ) 0 }
        = . x w ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) )
        ( slice_put [( Vec i )] . x w 0 ( fresh k ) )
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
