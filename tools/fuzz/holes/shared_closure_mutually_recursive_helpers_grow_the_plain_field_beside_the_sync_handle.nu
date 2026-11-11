// shared_closure_mutually_recursive_helpers_grow_the_plain_field_beside_the_sync_handle: a thread-shared closure hands its captured struct to `ping`, which calls `pong` (defined below it), which pushes to the struct's plain Vec and calls `ping` again. The closure sits in a struct in an Arc that eight threads run it out of, so every one of them grows the one buffer at once.
// Guard of #639's rule: the summaries of a cycle of functions are closed together, so the push in the second is a change by the first — whose own body changes nothing and is read before the second is defined.
// map: §6.5 | A3 | rejected | - | a thread-shared closure's helper calls a function below it that pushes to the plain Vec field and calls the helper back: a change of the capture, found round a cycle of two functions (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( vec_new [i] ) 1 } }

@ ping App a i d i k → v {
    ? > d 0 { ( pong a - d 1 k ) } {}
}

@ pong App a i d i k → v {
    ( vec_push [i] . a log k )
    ( ping a d k )
}

: Holder { ( @ v i ) f i tag }

@ hit ( Arc Holder ) a i n → v {
    : Holder h ( arc_get [Holder] a )
    : ( @ v i ) g . h f
    : ~ i j 0
    ~ < j n {
        ( g j )
        = j + j 1
    }
}

@ main → i {
    : App app ( mkapp )
    : ( @ v i ) work \ i k → v {
        ( ping app 2 k )
    }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        : ( @ v ) body \ → v { ( hit mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}
