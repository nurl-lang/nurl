// own_generic_named_weak_holding_a_share_crosses_counted_runs_clean: a program's own generic `: Weak [T] { T c i n }` at PNCounter, holding a share the spawner keeps, captured by eight threads
// Closed: agora #714, as for the plain struct.
// main ffce8adb: accepted (ASan: attempting double-free).
// map: §6.5 | B | runs-clean | - | agora #714: a program's own generic named Weak at PNCounter is counted at the crossing, which panics
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/dist/crdt.nu`

: Weak [T] { T c i n }

@ work ( Weak PNCounter ) wk i n → v { : ~ i k 0 ~ < k n { ( pncounter_inc . wk c + * . wk n 100000 k 1 ) = k + k 1 } }

@ main → i {
    : PNCounter hits ( pncounter_new )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Weak PNCounter ) wk @ ( Weak PNCounter ) { ( PNCounter_share hits ) t }
        : ( @ v ) body \ → v { ( work wk 1500 ) }
        ?? ( thread_spawn body ) { T th → { ( vec_push [Thread] ts th ) } F e → {} }
        = t + t 1
    }
    : ~ i q 0
    ~ < q ( vec_len [Thread] ts ) { : i joined ( thread_join ( vec_at [Thread] ts q ) ) = q + q 1 }
    ^ 0
}
