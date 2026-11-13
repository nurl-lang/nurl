// sync_closure_sending_on_fields_of_a_sync_capture_with_a_notsync_part_runs_clean: the shared closure sends on the Channels of `. app wb` and `. app wi`: a send is the Channel's own change, whichever instance holds it
// Guard for agora #719's fix: only a change the `% NotSync` part does not order itself is refused.
// main ff75baea: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #719: guard: sends through the fields of a Sync capture with a NotSync part
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: W [A] { ( Channel A ) c ( Vec A ) v }

@ wpush [A] ( W A ) w A x → v { ( vec_push [A] . w v x ) }

@ wsend [A] ( W A ) w A x → v { ( chan_send [A] . w c x ) }

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
    : ( @ v i ) work \ i k → v { ( wsend [b] . app wb T ) ( wsend [i] . app wi k ) }
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
