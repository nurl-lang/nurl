// shared_closure_grows_the_plain_vec_of_its_captured_share_handle: a closure eight threads run pushes to the plain Vec of the share handle it captured — a struct of the program's own with `Reg_share` / `Reg_drop`, an Arc over an Atomic and a Vec beside it. Copies of a `Reg` may be used on two threads (each share has a Vec of its own); the closure's one capture is one Vec, which every thread grows with no lock.
// Guard of agora #639's rule: sharing a handle and changing through one value of it are asked apart (__thr_share_ok, __thr_orders_itself). The Sync-closure rule skipped every capture whose type could be shared.
// main: accepted — ASan double free in the Vec's growth.
// map: §6.5 | A3 | rejected | - | a thread-shared closure pushes to the plain Vec of the own share handle it captured (an Arc and a Vec beside it): a capture is exempt only where every part of it orders its own changes (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/core/vec.nu`

: Reg { ( Arc Atomic ) hits ( Vec i ) mine }

@ Reg_share Reg x → Reg { ^ @ Reg { ( arc_clone [Atomic] . x hits ) ( vec_new [i] ) } }

@ Reg_drop sink Reg x → v {}

@ mkreg → Reg { ^ @ Reg { ( arc_new [Atomic] ( atomic_new 0 ) ) ( vec_new [i] ) } }

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
    : Reg reg ( mkreg )
    : ( @ v i ) work \ i k → v {
        ( vec_push [i] . reg mine k )
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
