// sync_closure_changing_a_notsync_instance_field_of_a_sync_capture_is_refused: a closure kept in an Arc and run by 8 threads hands `. app wi` to a function that grows its plain Vec; `App` is asserted `unsafe % Sync`, its `( W i )` field `% NotSync`
// Closed: agora #719, a type asserted `% Sync` that holds a `% NotSync` part by value does not order itself.
// main ff75baea: accepted (8 threads grow the one plain Vec; ASan: attempting double-free on 6 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #719: a Sync capture's NotSync field grown by a shared closure
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

@ mkapp → App { ^ @ App { @ ( W i ) { ( chan_new [i] ) ( vec_new [i] ) } @ ( W b ) { ( chan_new [b] ) ( vec_new [b] ) } } }

: Holder { ( @ v i ) f i tag }

@ hit ( Arc Holder ) a i n → v {
    : Holder h ( arc_get [Holder] a )
    : ( @ v i ) g . h f
    : ~ i j 0
    ~ < j n { ( g j ) = j + j 1 }
}

@ main → i {
    : App app ( mkapp )
    : ( @ v i ) work \ i k → v { ( wpush [i] . app wi k ) }
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
