// own_struct_named_weak_holding_a_share_crosses_counted_runs_clean: a program's own `: Weak { PNCounter c i n }` holding a share of a counter the spawner keeps, captured by eight threads
// Closed: agora #714, the run-time crossing check walks a type by what it is: the struct is walked by its fields and the crossing panics, as for the same struct named `Holder`.
// main ffce8adb: accepted (ASan: attempting double-free).
// map: §6.5 | B | runs-clean | - | agora #714: a program's own struct named Weak holding a PNCounter share is counted at the crossing, which panics
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/dist/crdt.nu`

: Weak { PNCounter c i n }

@ work Weak wk i n → v { : ~ i k 0 ~ < k n { ( pncounter_inc . wk c + * . wk n 100000 k 1 ) = k + k 1 } }

@ main → i {
    : PNCounter hits ( pncounter_new )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : Weak wk @ Weak { ( PNCounter_share hits ) t }
        : ( @ v ) body \ → v { ( work wk 1500 ) }
        ?? ( thread_spawn body ) { T th → { ( vec_push [Thread] ts th ) } F e → {} }
        = t + t 1
    }
    : ~ i q 0
    ~ < q ( vec_len [Thread] ts ) { : i joined ( thread_join ( vec_at [Thread] ts q ) ) = q + q 1 }
    ^ 0
}
