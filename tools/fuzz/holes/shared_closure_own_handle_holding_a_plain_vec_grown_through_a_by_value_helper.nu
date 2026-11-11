// shared_closure_own_handle_holding_a_plain_vec_grown_through_a_by_value_helper: a closure eight threads run hands a field of its captured struct — a struct of the program's own that is a handle (`Bag_drop`) and holds a plain Vec — by value to a function that pushes to that Vec: every thread grows the one buffer with no lock.
// Guard of agora #639's rule, the closure side of arc_payload_own_handle_holding_a_plain_vec_grown_through_a_by_value_helper: a handle nobody marked synchronises itself by what it is made of (__ty_selfsync), and a plain Vec is one state every borrow grows in place.
// main: refused. A first cut of #639 took every handle not held in an rcbox: ASan double free.
// map: §6.5 | A3 | rejected | - | a thread-shared closure hands its captured struct's own-handle field (a drop hook, a plain Vec inside) by value to a function that pushes to the Vec: a handle synchronises itself only where every part of it does (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Bag { ( Vec i ) v }

@ Bag_drop sink Bag x → v {}

: App { ( Channel i ) jobs Bag bag i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) @ Bag { ( vec_new [i] ) } 1 } }

@ grow Bag j i k → v { ( vec_push [i] . j v k ) }

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
        ( grow . app bag k )
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
