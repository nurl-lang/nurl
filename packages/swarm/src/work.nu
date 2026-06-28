// packages/swarm/src/work.nu — the real workloads the cluster runs.
//
// A workload is a pure function over a numeric range that the coordinator
// shards into many independent chunks; dist/ring routes each chunk to its
// owning worker, the worker runs the registered handler, and the coordinator
// sums the partial results. The work is genuine CPU — primes are counted by
// trial division, not looked up — so a bigger range is a bigger real load, and
// adding workers measurably shares it.
//
// Two kinds, both verifiable by a closed form so a test can pin the answer:
//   * PRIMES   count of primes in [lo, hi)         (π(10^6) = 78498)
//   * SUMSQ    Σ k² for k in [lo, hi), wrapping i64 (n(n+1)(2n+1)/6 closed form)
//
// chunk payload : [lo:8 BE][hi:8 BE]
// result        : [value:8 BE]

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

@ kind_primes → i { ^ 10 }

@ kind_sumsq → i { ^ 11 }

// Is n prime? Trial division to √n — deliberately the honest O(√n) work.
@ is_prime i n → b {
    ? < n 2 { ^ F } {}
    ? == n 2 { ^ T } {}
    ? == 0 % n 2 { ^ F } {}
    : ~ i d 3
    : ~ b prime T
    ~ & prime <= * d d n {
        ? == 0 % n d { = prime F } {}
        = d + d 2
    }
    ^ prime
}

// Count primes in [lo, hi).
@ count_primes i lo i hi → i {
    : ~ i c 0
    : ~ i k lo
    ~ < k hi { ? ( is_prime k ) { = c + c 1 } {} = k + k 1 }
    ^ c
}

// Σ k² for k in [lo, hi), wrapping (matches the i64 the closed form is taken mod).
@ sum_squares i lo i hi → i {
    : ~ i acc 0
    : ~ i k lo
    ~ < k hi { = acc + acc * k k = k + k 1 }
    ^ acc
}

// ── chunk codec ───────────────────────────────────────────────────

@ chunk_payload i lo i hi → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( bytes_push_u64_be b # u64 lo )
    ( bytes_push_u64_be b # u64 hi )
    ^ b
}

@ chunk_lo ( Vec u ) p → i { ^ ?? ( bytes_read_u64_be p 0 ) { T x → # i x F → 0 } }

@ chunk_hi ( Vec u ) p → i { ^ ?? ( bytes_read_u64_be p 8 ) { T x → # i x F → 0 } }

@ result_encode i value → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( bytes_push_u64_be b # u64 value )
    ^ b
}

@ result_decode ( Vec u ) p → i { ^ ?? ( bytes_read_u64_be p 0 ) { T x → # i x F → 0 } }

// ── handlers (opaque bytes → bytes), the shape dist/job registers ──

@ primes_handler → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : i lo ( chunk_lo p )
        : i hi ( chunk_hi p )
        ^ ( result_encode ( count_primes lo hi ) )
    }
}

@ sumsq_handler → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : i lo ( chunk_lo p )
        : i hi ( chunk_hi p )
        ^ ( result_encode ( sum_squares lo hi ) )
    }
}

// ── sharding: split [lo, hi) into n contiguous chunks ─────────────
// Chunk i is [lo + i·base, …); the last chunk absorbs the remainder. Empty
// chunks (range smaller than n) are produced as lo==hi and the handler returns
// 0, so the aggregate stays correct regardless of n.

: Chunk { i lo i hi }

@ shard i lo i hi i n → ( Vec s ) {
    : ( Vec s ) out ( vec_new [s] )
    : i total ? > hi lo - hi lo 0
    : i base / total n
    : ~ i i 0
    ~ < i n {
        : i clo + lo * i base
        : i chi ? == i - n 1 hi + lo * + i 1 base
        : *Chunk c # *Chunk ( nurl_alloc Z Chunk )
        = . c lo clo
        = . c hi chi
        ( vec_push [s] out # s c )
        = i + i 1
    }
    ^ out
}

@ shard_free ( Vec s ) chunks → v {
    : i n ( vec_len [s] chunks )
    : ~ i k 0
    ~ < k n { ?? ( vec_get [s] chunks k ) { T pp → ?!= # i pp 0 { ( nurl_free pp ) } {} F → {} } = k + k 1 }
    ( vec_free [s] chunks )
}

// A ring key for chunk index i: 8 BE bytes so distinct chunks hash to distinct
// ring points (FNV-1a/64 in ring_owner) and spread across the worker set.
@ chunk_key i idx → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( bytes_push_u64_be b # u64 idx )
    ^ b
}
