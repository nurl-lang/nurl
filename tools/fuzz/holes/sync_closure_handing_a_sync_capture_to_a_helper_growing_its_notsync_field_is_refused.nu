// sync_closure_handing_a_sync_capture_to_a_helper_growing_its_notsync_field_is_refused: the shared closure hands the whole `app` to a helper that grows `. a wi`
// Closed: agora #719, the helper's change of its `App` parameter is no longer excused by App's `% Sync` (the parameter does not order itself).
// main ff75baea: accepted (8 threads grow the one plain Vec; ASan: attempting double-free on 6 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #719: a helper growing a Sync capture's NotSync field
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

@ apush App a i k → v { ( wpush [i] . a wi k ) }

@ hit ( Arc Holder ) a i n → v {
    : Holder h ( arc_get [Holder] a )
    : ( @ v i ) g . h f
    : ~ i j 0
    ~ < j n { ( g j ) = j + j 1 }
}

@ main → i {
    : App app ( mkapp )
    : ( @ v i ) work \ i k → v { ( apush app k ) }
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
