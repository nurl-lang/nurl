// closure_shared_arc_clone_of_captured_field.nu — agora #684: a closure
// several threads run (kept in an Arc) takes its own clone of an Arc that
// is a FIELD of the struct it captured, `( arc_clone [Pl] . a ap )`. Only
// the share count changes, atomically — as for an Arc captured itself,
// which was accepted. It was refused: "the closure changes 'a' when it runs
// (it hands it to 'arc_clone', which changes it)". The rule now asks what
// the field path names, through fields held by value.

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: Pl { ( Vec i ) v i n }
: App { ( Arc Pl ) ap i n }
: Holder { ( @ i i ) f i tag }

@ main → i {
    : App a @ App { ( arc_new [Pl] @ Pl { ( vec_new [i] ) 0 } ) 1 }
    : ( @ i i ) work \ i k → i {
        : ( Arc Pl ) c2 ( arc_clone [Pl] . a ap )
        ^ + k ( vec_len [i] . ( arc_get [Pl] c2 ) v )
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
