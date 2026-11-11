// notsync_instance_of_a_generic_marked_sync_grown_out_of_an_arc_through_two_generic_functions: `unsafe % Sync W { }` promises every instance of `: W [A] { ( Channel A ) c ( Vec A ) v }` synchronises itself, and `% NotSync ( W i ) { }` takes the promise back for one. A function handed an Arc's payload hands the `( W i )` field through `f2 [T]` → `f1 [T]` to a trait method that pushes to its plain Vec; eight threads holding clones of the Arc run it at once and grow the one buffer.
// main: accepted — the frozen-Arc rule asked the positive marker first, and it is found by the generic's bare name: the instance's own `NotSync` was never read (ASan: double-free).
// map: §6.5 | A3 | rejected | - | a `( W i )` marked NotSync where `W` is marked Sync, read out of an Arc's payload and grown two generic functions deep: a negative marker on an instance outranks the generic's positive one in every rule that asks whether a type synchronises itself (agora #693)
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
        ( f2 [( W i )] . . ( arc_get [App] mine ) o wi k )
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
