// shared_closure_helpers_grow_the_plain_field_of_a_field_beside_a_sync_handle: a thread-shared closure hands its captured struct on, two calls deep, to a function that pushes to `. . a in v`: the plain Vec of the struct's inner struct, the field beside that inner struct's Channel. The closure sits in a struct in an Arc that eight threads run it out of, so every one of them grows the one buffer at once.
// Guard of #639's rule: a self-synchronising handle one field further in excuses nothing beside it; the push is a change of the capture.
// map: §6.5 | A3 | rejected | - | a thread-shared closure's helpers push to `. . a in v`, the plain Vec of a field of the capture, beside the Channel `. . a in c`, two calls deep: a change of the capture (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Inner { ( Vec i ) v ( Channel i ) c }

: App { Inner in i n }

@ mkapp → App { ^ @ App { @ Inner { ( vec_new [i] ) ( chan_new [i] ) } 1 } }

@ second App a i k → v { ( vec_push [i] . . a in v k ) }

@ first App a i k → v { ( second a k ) }

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
        ( first app k )
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
