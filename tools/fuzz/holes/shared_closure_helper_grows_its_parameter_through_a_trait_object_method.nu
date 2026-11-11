// shared_closure_helper_grows_its_parameter_through_a_trait_object_method: a thread-shared closure hands its captured struct to a function that calls a trait-object method on it (`( grow_it d a k )`, `d` a `%Grower`), and the one impl pushes to the struct's plain Vec. The closure sits in a struct in an Arc that eight threads run it out of, so every one of them grows the one buffer at once.
// Guard of #639's rule: a dyn call answers with the union of its impls, and an impl that changes plain data through the by-value argument changes the capture.
// map: §6.5 | A3 | rejected | - | a thread-shared closure's helper hands its parameter to a trait-object method whose impl pushes to the plain Vec field: a change of the capture through a dyn call (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( vec_new [i] ) 1 } }

% Grower [T] { @ grow_it T self App a i k → v }

: Plain { i tag }

% Grower Plain { @ grow_it Plain p App a i k → v { ( vec_push [i] . a log k ) } }

@ via App a i k → v {
    : Plain m @ Plain { 1 }
    : %Grower d ( dyn Grower m )
    ( grow_it d a k )
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
        ( via app k )
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
