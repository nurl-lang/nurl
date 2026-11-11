// sync_instance_beside_a_notsync_sibling_sends_out_of_an_arc_through_three_generic_functions_runs_clean: `unsafe % Sync W { }` with `% NotSync ( W i ) { }`: a function handed an Arc's payload, on eight threads, hands the `( W b )` field through `f3 [T]` → `f2 [T]` → `f1 [T]` to a trait method that sends on its Channel.
// The control for notsync_instance_of_a_generic_marked_sync_grown_out_of_an_arc_through_three_generic_functions.
// map: §6.5 | A3 | runs-clean | - | guard: the `( W b )` field of an Arc's payload goes three generic functions deep and sends on its Channel while `( W i )` is marked NotSync (agora #693)
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

% Touch [T] { @ touch T self i k → v }

% Touch ( W i ) { @ touch ( W i ) self i k → v { ( wpush [i] self k ) } }

% Touch ( W b ) { @ touch ( W b ) self i k → v { ( wsend [b] self T ) } }

@ f1 [T] T x i k → v { ( touch x k ) }

@ f2 [T] T x i k → v { ( f1 [T] x k ) }

@ f3 [T] T x i k → v { ( f2 [T] x k ) }

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( f3 [( W b )] . . ( arc_get [App] mine ) o wb k )
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
