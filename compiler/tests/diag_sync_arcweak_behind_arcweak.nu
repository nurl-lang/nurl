// An ArcWeak is its Arc to both questions, at every depth: behind two weak
// handles the payload is still one value two threads can upgrade to, and
// what the error names is the part of it that may not be shared — the Rc —
// not the weak handle in front of it (agora #690).
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: Holder { ( Rc i ) r }

@ main → i {
    : ( Arc Holder ) a ( arc_new [Holder] @ Holder { ( rc_new [i] 5 ) } )
    : ( Arc ( ArcWeak Holder ) ) aa ( arc_new [( ArcWeak Holder )] ( arc_downgrade [Holder] a ) )
    : ( ArcWeak ( ArcWeak Holder ) ) ww ( arc_downgrade [( ArcWeak Holder )] aa )
    : ( @ v ) body \ → v {
        ?? ( arc_weak_upgrade [( ArcWeak Holder )] ww ) {
            T up → {}
            F → {}
        }
    }
    ?? ( thread_spawn body ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
