// thread_own_handle_of_sync_parts.nu — a handle of the program's own
// synchronises itself where every part of it does (docs/MEMORY.md §6.5;
// agora #639). `Kit` is a handle (`Kit_drop`, `Kit_share`) made of nothing
// but Arcs — over a Locked Vec and an Atomic — and a number: a closure
// several threads run hands its captured struct's Kit, by value, to a
// function that pushes under the lock and counts in the Atomic, and so
// does a function handed an Arc's payload. Every change is made through a
// part that orders it.
//
// The control for diag_sync_closure_own_handle_plain_vec.nu: a handle
// holding a plain Vec is one buffer every borrow grows with no lock.
//
// Spawns real pthreads, so it carries the same declaration as
// thread_basic / arc_threads.
// requires: live

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/core/vec.nu`

: Kit { ( Arc ( Locked ( Vec i ) ) ) rows ( Arc Atomic ) seen i id }

@ Kit_share Kit x → Kit { ^ @ Kit { ( arc_clone [( Locked ( Vec i ) )] . x rows ) ( arc_clone [Atomic] . x seen ) . x id } }

@ Kit_drop sink Kit x → v {}

: App { Kit kit i n }

@ file Kit x i k → v {
    ( locked_update [( Vec i )] ( arc_get [( Locked ( Vec i ) )] . x rows ) \ inout ( Vec i ) q → v { ? < ( vec_len [i] q ) 64 { ( vec_push [i] q k ) } {} } )
    : i before ( atomic_add ( arc_get [Atomic] . x seen ) 1 )
}

: Holder { ( @ v i ) f i tag }

@ run ( Arc Holder ) a i n → v {
    : Holder h ( arc_get [Holder] a )
    : ( @ v i ) f . h f
    : ~ i k 0
    ~ < k n {
        ( f k )
        = k + k 1
    }
}

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( file . ( arc_get [App] mine ) kit k )
        = k + k 1
    }
}

@ mkkit → Kit { ^ @ Kit { ( arc_new [( Locked ( Vec i ) )] ( locked_new [( Vec i )] ( vec_new [i] ) ) ) ( arc_new [Atomic] ( atomic_new 0 ) ) 1 } }

@ main → i {
    // Through a thread-shared closure's capture. (`seen` is a second handle
    // of the Kit's counter: the closure takes `app` with it.)
    : Kit kit ( mkkit )
    : ( Arc Atomic ) seen ( arc_clone [Atomic] . kit seen )
    : App app @ App { kit 1 }
    : ( @ v i ) work \ i k → v { ( file . app kit k ) }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    // Through an Arc's payload.
    : ( Arc App ) frozen ( arc_new [App] @ App { ( mkkit ) 2 } )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        : ( Arc App ) theirs ( arc_clone [App] frozen )
        : ( @ v ) body \ → v {
            ( run mine 250 )
            ( reader theirs 250 )
        }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ h ts { ( thread_join h ) }
    ( nurl_println ( nurl_str_int ( atomic_load ( arc_get [Atomic] seen ) ) ) )
    ( nurl_println ( nurl_str_int ( atomic_load ( arc_get [Atomic] . . ( arc_get [App] frozen ) kit seen ) ) ) )
    ^ 0
}
