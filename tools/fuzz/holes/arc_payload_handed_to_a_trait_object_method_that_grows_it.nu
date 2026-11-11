// arc_payload_handed_to_a_trait_object_method_that_grows_it: a function handed an Arc's payload calls a trait-object method on it (`( grow_it d a k )`, `d` a `%Grower`), and the one impl pushes to the payload's plain Vec. Eight threads each hold a clone of the Arc and run the function at once, so every one of them grows the one buffer.
// Guard of #639's rule on the Arc side: a dyn call answers with the union of its impls; the payload stays frozen.
// map: §6.5 | A3 | rejected | - | a function handed an Arc's payload hands it to a trait-object method whose impl pushes to the plain Vec field: the payload stays frozen through a dyn call (agora #639)
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

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( via ( arc_get [App] mine ) k )
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
