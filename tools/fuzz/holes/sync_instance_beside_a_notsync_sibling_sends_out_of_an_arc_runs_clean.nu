// sync_instance_beside_a_notsync_sibling_sends_out_of_an_arc_runs_clean: `unsafe % Sync W { }` with `% NotSync ( W i ) { }`: a function handed an Arc's payload, on eight threads, sends on the Channel of the `( W b )` field — the instance the negative marker does not name keeps the generic's promise.
// The control for the notsync_instance_of_a_generic_marked_sync_* probes.
// map: §6.5 | A3 | runs-clean | - | guard: the `( W b )` field of an Arc's payload sends on its Channel on eight threads while `( W i )` is marked NotSync: a negative marker reaches the instance it names only (agora #693)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: W [A] { ( Channel A ) c ( Vec A ) v }

@ wpush [A] ( W A ) w A x → v { ( vec_push [A] . w v x ) }

@ wsend [A] ( W A ) w A x → v { : b o ( chan_send [A] . w c x ) }

unsafe % Sync W {}

% NotSync ( W i ) {}

: Outer { ( W i ) wi ( W b ) wb }

unsafe % Sync Outer {}

: App { ( Channel i ) h Outer o i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) @ Outer { @ ( W i ) { ( chan_new [i] ) ( vec_new [i] ) } @ ( W b ) { ( chan_new [b] ) ( vec_new [b] ) } } 1 } }

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( wsend [b] . . ( arc_get [App] mine ) o wb T )
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc App ) mine ( arc_clone [App] shared )
        : ( @ v ) body \ → v { ( reader mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F e → { ( nurl_eprintln `spawn failed` ) }
        }
        = t + t 1
    }
    : ~ i q 0
    ~ < q ( vec_len [Thread] ts ) { : i joined ( thread_join ( vec_at [Thread] ts q ) ) = q + q 1 }
    ( nurl_eprintln `ran` )
    ^ 0
}
