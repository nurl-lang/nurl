// A closure several threads run (kept in an Arc) that changes its own
// rw_get copy of a captured RwLocked's value changes nothing the threads
// share: rw_get hands back a copy the closure owns (agora #685, refused
// before the conditional-effect work of #639 / #1838; pinned here).
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rwlock.nu`

: St { ( Vec i ) v i n }
: App { ( RwLocked St ) rw i n }
: Holder { ( @ i i ) f i tag }

@ sg St s i k → v { ( vec_push [i] . s v k ) }

@ main → i {
    : App a @ App { ( rw_new [St] @ St { ( vec_new [i] ) 0 } ) 1 }
    : ( @ i i ) work \ i k → i {
        ( sg ( rw_get [St] . a rw ) k )
        ^ k
    }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    : ( Arc Holder ) mine ( arc_clone [Holder] shared )
    : ( @ v ) body \ → v {
        : Holder h ( arc_get [Holder] mine )
        : ( @ i i ) g . h f
        : i n ( g 1 )
    }
    ?? ( thread_spawn body ) { T th → { : i joined ( thread_join th ) } F e → {} }
    : Holder h0 ( arc_get [Holder] shared )
    : ( @ i i ) g0 . h0 f
    ^ - ( g0 0 ) 0
}
