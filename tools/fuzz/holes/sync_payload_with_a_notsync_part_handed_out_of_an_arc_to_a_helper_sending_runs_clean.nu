// sync_payload_with_a_notsync_part_handed_out_of_an_arc_to_a_helper_sending_runs_clean: 8 threads hand the same payload to a helper that only sends on the Channels of its `( W i )` and `( W b )` fields
// Guard for agora #719's frozen-payload fix: a send is the Channel's own change, whichever instance holds it.
// main ff75baea: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #719 guard: an Arc's Sync payload with a NotSync part, only sent through
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: W [A] { ( Channel A ) c ( Vec A ) v }

@ wpush [A] ( W A ) w A x → v { ( vec_push [A] . w v x ) }

unsafe % Sync W {}

% NotSync ( W i ) {}

: App { ( W i ) wi ( W b ) wb }

unsafe % Sync App {}

@ wsend [A] ( W A ) w A x → v { ( chan_send [A] . w c x ) }

@ asend App a i k → v { ( wsend [i] . a wi k ) ( wsend [b] . a wb T ) }

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n { ( asend ( arc_get [App] mine ) k ) = k + k 1 }
}

@ main → i {
    : ( Arc App ) a ( arc_new [App] @ App { @ ( W i ) { ( chan_new [i] ) ( vec_new [i] ) } @ ( W b ) { ( chan_new [b] ) ( vec_new [b] ) } } )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i j 0
    ~ < j 8 {
        : ( Arc App ) mine ( arc_clone [App] a )
        : !Thread ThreadErr r ( thread_spawn \ → v { ( reader mine 3000 ) } )
        ?? r { T t → { ( vec_push [Thread] ts t ) } F e → {} }
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    ^ 0
}
