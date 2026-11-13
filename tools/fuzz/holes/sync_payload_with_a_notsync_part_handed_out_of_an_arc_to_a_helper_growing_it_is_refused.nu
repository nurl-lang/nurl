// sync_payload_with_a_notsync_part_handed_out_of_an_arc_to_a_helper_growing_it_is_refused: 8 threads hand an Arc's App payload, asserted `unsafe % Sync`, to a helper that grows its `( W i )` field, asserted `% NotSync`
// Closed: agora #719, the frozen-payload rule's mask excuses a value asserted `% Sync` only where it holds no part asserted `% NotSync`.
// main ff75baea: accepted (8 threads grow the one plain Vec; ASan: attempting double-free on 6 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #719: an Arc's Sync payload with a NotSync part handed to a helper that grows it
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

@ apush App a i k → v { ( wpush [i] . a wi k ) }

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n { ( apush ( arc_get [App] mine ) k ) = k + k 1 }
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
