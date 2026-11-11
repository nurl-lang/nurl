// arc_payload_mutually_recursive_helpers_grow_the_plain_field_beside_the_sync_handle: a function handed an Arc's payload calls `ping`, which calls `pong` (defined below it), which pushes to the payload's plain Vec and calls `ping` again. Eight threads each hold a clone of the Arc and run the function at once, so every one of them grows the one buffer.
// Guard of #639's rule on the Arc side: the summaries of a cycle of functions are closed together; the payload stays frozen.
// map: §6.5 | A3 | rejected | - | a function handed an Arc's payload calls a function below it that pushes to the plain Vec field and calls it back: the payload stays frozen round a cycle of two functions (agora #639)
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

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( ping ( arc_get [App] mine ) 2 k )
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
