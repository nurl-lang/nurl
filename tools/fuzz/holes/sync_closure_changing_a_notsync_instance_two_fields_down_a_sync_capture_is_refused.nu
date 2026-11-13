// sync_closure_changing_a_notsync_instance_two_fields_down_a_sync_capture_is_refused: the same through `. . app a wi`, `Outer` and `App` both asserted `unsafe % Sync`
// Closed: agora #719, the `% NotSync` part is looked for through the struct fields held by value.
// main ff75baea: accepted (8 threads grow the one plain Vec; ASan: attempting double-free on 6 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #719: a NotSync instance two fields down a Sync capture
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: W [A] { ( Channel A ) c ( Vec A ) v }

@ wpush [A] ( W A ) w A x → v { ( vec_push [A] . w v x ) }

unsafe % Sync W {}

% NotSync ( W i ) {}

: App { ( W i ) wi ( W b ) wb }

unsafe % Sync App {}

: Outer { App a i n }

unsafe % Sync Outer {}

@ mkapp → App { ^ @ App { @ ( W i ) { ( chan_new [i] ) ( vec_new [i] ) } @ ( W b ) { ( chan_new [b] ) ( vec_new [b] ) } } }

: Holder { ( @ v i ) f i tag }

@ hit ( Arc Holder ) a i n → v {
    : Holder h ( arc_get [Holder] a )
    : ( @ v i ) g . h f
    : ~ i j 0
    ~ < j n { ( g j ) = j + j 1 }
}

@ main → i {
    : Outer app @ Outer { ( mkapp ) 1 }
    : ( @ v i ) work \ i k → v { ( wpush [i] . . app a wi k ) }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        : ( @ v ) body \ → v { ( hit mine 3000 ) }
        ?? ( thread_spawn body ) { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}
