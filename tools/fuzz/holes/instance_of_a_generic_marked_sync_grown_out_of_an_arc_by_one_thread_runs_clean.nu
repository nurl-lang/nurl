// instance_of_a_generic_marked_sync_grown_out_of_an_arc_by_one_thread_runs_clean: `unsafe % Sync W { }` and no negative marker: a function handed an Arc's payload hands the `( W i )` field through `f2 [T]` → `f1 [T]` to a trait method that pushes to its plain Vec. The program's own unsafe promise says a `W` synchronises itself, so the frozen-Arc rule takes its word — the promise is the program's to keep, and this one keeps it by running a single thread.
// The control for the notsync_instance_of_a_generic_marked_sync_* probes: without the `NotSync` the same call is accepted.
// map: §6.5 | A3 | runs-clean | - | guard: with `unsafe % Sync W` and no NotSync, a `( W i )` read out of an Arc's payload is grown two generic functions deep: the positive marker still excuses what no negative one takes back (agora #693)
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
        ( f2 [( W i )] . . ( arc_get [App] mine ) o wi k )
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 1 {
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
