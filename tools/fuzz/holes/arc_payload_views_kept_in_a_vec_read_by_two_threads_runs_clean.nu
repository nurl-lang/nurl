// arc_payload_views_kept_in_a_vec_read_by_two_threads_runs_clean: Slices of an Arc's payload pushed into local Vecs, read back by two threads, the Vecs moved, grown, truncated and cleared
// Guard for agora #682's fix: a view read back out of a holder is one, and only a change through it is refused; the holder itself is changed freely.
// main 07d73fb1: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #682 guard: reading payload views kept in a Vec, and changing the Vec, stay accepted
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

@ total ( Vec ( Slice ( Vec i ) ) ) ws → i {
    : ~ i s 0
    ~ w ws { = s + s ( slice_len [( Vec i )] w ) }
    ^ s
}

@ writer ( Arc ( Vec ( Vec i ) ) ) mine i n → v {
    : ~ i k 0
    : ~ i s 0
    ~ < k n {
        : ( Vec ( Slice ( Vec i ) ) ) ws ( vec_new [( Slice ( Vec i ) )] )
        ( vec_push [( Slice ( Vec i ) )] ws ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) )
        = s + s ( total ws )
        : ( Vec ( Slice ( Vec i ) ) ) ws2 ws
        ( vec_push [( Slice ( Vec i ) )] ws2 ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) )
        = s + s ( total ws2 )
        ( vec_truncate [( Slice ( Vec i ) )] ws2 0 )
        = k + k 1
    }
    ? != s * n 3 { ( nurl_println `wrong` ) } {}
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
