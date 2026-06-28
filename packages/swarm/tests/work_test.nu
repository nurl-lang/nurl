// packages/swarm/tests/work_test.nu — offline tests for the pure compute core.
//
// Everything the cluster relies on for a CORRECT distributed answer is pure and
// checkable without a socket: the workloads themselves, and — critically — that
// sharding partitions a range exactly (no gap, no overlap) so the sum of the
// chunk results equals the whole-range result. Run from the package root:
//
//   NURL_STDLIB=<repo> ./nurl.sh tests/work_test.nu /tmp/wt && /tmp/wt

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/dist/ring.nu`
$ `src/work.nu`
$ `src/census.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ pi s label i a i b → v {
    ( nurl_print label ) ( nurl_print_int a )
    ( nurl_print ? == a b ` == ` ` != ` ) ( nurl_print_int b ) ( nurl_print `\n` )
}

// Sum a workload over a sharded range — the exact thing the coordinator does.
@ shard_sum_primes i lo i hi i n → i {
    : ( Vec s ) cs ( shard lo hi n )
    : ~ i total 0
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] cs k ) { T x → x F → # s 0 }
        : *Chunk c # *Chunk pp
        = total + total ( count_primes . c lo . c hi )
        = k + k 1
    }
    ( shard_free cs )
    ^ total
}

@ shard_sum_sumsq i lo i hi i n → i {
    : ( Vec s ) cs ( shard lo hi n )
    : ~ i total 0
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] cs k ) { T x → x F → # s 0 }
        : *Chunk c # *Chunk pp
        = total + total ( sum_squares . c lo . c hi )
        = k + k 1
    }
    ( shard_free cs )
    ^ total
}

@ pk_demo i seed → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i k 0
    ~ < k 32 { ( vec_push [u] v # u + seed k ) = k + k 1 }
    ^ v
}

@ main → i {
    // ── workloads vs known closed forms ──────────────────────────
    ( pi `pi(100):  ` ( count_primes 1 100 ) 25 )
    ( pi `pi(1000): ` ( count_primes 1 1000 ) 168 )
    ( pi `sumsq[1,11): ` ( sum_squares 1 11 ) 385 )

    // ── sharding partitions a range EXACTLY ──────────────────────
    // Any chunk count must reproduce the whole-range answer.
    ( pb `primes shard n=1:  ` == ( shard_sum_primes 1 1000 1 ) 168 )
    ( pb `primes shard n=7:  ` == ( shard_sum_primes 1 1000 7 ) 168 )
    ( pb `primes shard n=64: ` == ( shard_sum_primes 1 1000 64 ) 168 )
    ( pb `primes shard n>range: ` == ( shard_sum_primes 1 50 200 ) ( count_primes 1 50 ) )
    ( pb `sumsq shard n=8:  ` == ( shard_sum_sumsq 0 100 8 ) ( sum_squares 0 100 ) )
    ( pb `sumsq shard n=13: ` == ( shard_sum_sumsq 0 100 13 ) ( sum_squares 0 100 ) )

    // ── chunk + result codecs round-trip ─────────────────────────
    : ( Vec u ) cp ( chunk_payload 1234 5678 )
    ( pb `chunk lo: ` == ( chunk_lo cp ) 1234 )
    ( pb `chunk hi: ` == ( chunk_hi cp ) 5678 )
    ( vec_free [u] cp )
    : ( Vec u ) rb ( result_encode 999999 )
    ( pb `result rt: ` == ( result_decode rb ) 999999 )
    ( vec_free [u] rb )

    // ── census HELLO codec round-trips ───────────────────────────
    : ( Vec u ) pk ( pk_demo 3 )
    : ( Vec u ) hb ( hello_build 42 ( role_worker ) 1 pk )
    : Hello h ( hello_decode hb )
    ( pb `hello id:   ` == . h id 42 )
    ( pb `hello role: ` == . h role ( role_worker ) )
    ( pb `hello want: ` == . h want 1 )
    ( pb `hello pk:   ` ( bytes_eq . h pubkey pk ) )
    ( hello_free h )
    ( vec_free [u] hb )

    // ── roster folds a worker once (idempotent ring membership) ──
    : *Ring ring ( ring_new )
    : *Roster r ( roster_new )
    : b first ( roster_add r ring pk 42 64 )
    : b dup ( roster_add r ring pk 42 64 )
    ( pb `roster add first: ` first )
    ( pb `roster dedup:     ` ! dup )
    ( pb `roster count==1:  ` == ( roster_count r ) 1 )
    ( roster_free r )
    ( ring_free ring )
    ( vec_free [u] pk )

    ^ 0
}
