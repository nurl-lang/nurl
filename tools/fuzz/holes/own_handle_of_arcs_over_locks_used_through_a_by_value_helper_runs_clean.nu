// own_handle_of_arcs_over_locks_used_through_a_by_value_helper_runs_clean: a struct of the program's own that is a handle (`Kit_drop`, `Kit_share`) and is made of nothing but Arcs — over a Locked Vec and an Atomic — is read out of an Arc's payload and out of a thread-shared closure's capture and handed by value to a function that pushes under the lock and counts in the Atomic, on eight threads.
// Every change is made through a part that synchronises itself, so the handle does (__ty_selfsync): nurldb's Store is this shape. The control for arc_payload_own_handle_holding_a_plain_vec_grown_through_a_by_value_helper and its shared_closure_ twin.
// map: §6.5 | A3 | runs-clean | - | a program's own handle made of Arcs over a lock and an Atomic, read out of `( arc_get a )` and handed by value to a function that pushes under the lock: a handle whose every part synchronises itself does (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Kit { ( Arc ( Locked ( Vec i ) ) ) rows ( Arc Atomic ) seen i id }

@ Kit_share Kit x → Kit { ^ @ Kit { ( arc_clone [( Locked ( Vec i ) )] . x rows ) ( arc_clone [Atomic] . x seen ) . x id } }

@ Kit_drop sink Kit x → v {}

: App { ( Channel i ) jobs Kit kit i n }

@ mkapp → App {
    : Kit kit @ Kit { ( arc_new [( Locked ( Vec i ) )] ( locked_new [( Vec i )] ( vec_new [i] ) ) ) ( arc_new [Atomic] ( atomic_new 0 ) ) 1 }
    ^ @ App { ( chan_new [i] ) kit 1 }
}

@ file Kit x i k → v {
    ( locked_update [( Vec i )] ( arc_get [( Locked ( Vec i ) )] . x rows ) \ inout ( Vec i ) q → v { ? < ( vec_len [i] q ) 64 { ( vec_push [i] q k ) } {} } )
    : i before ( atomic_add ( arc_get [Atomic] . x seen ) 1 )
}

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( file . ( arc_get [App] mine ) kit k )
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
