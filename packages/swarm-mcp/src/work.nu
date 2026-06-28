// packages/swarm-mcp/src/work.nu — the distributed map-reduce the cluster runs.
//
// A task is: evaluate an expression kernel (expr.nu) over an integer range
// [lo, hi) and fold the results with a reduce op. The coordinator shards the
// range; dist/ring routes each chunk to its owning worker; the worker parses
// the kernel once and folds it over its sub-range; the coordinator combines the
// partial folds. Every reduce op is associative, so sharding is exact.
//
//   reduce op : 0 sum · 1 product · 2 min · 3 max · 4 count (of truthy map)
//   chunk     : [op:1][lo:8 BE][hi:8 BE][expr bytes…]
//   result    : [value:8 BE]

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `expr.nu`

@ red_sum → i { ^ 0 }

@ red_product → i { ^ 1 }

@ red_min → i { ^ 2 }

@ red_max → i { ^ 3 }

@ red_count → i { ^ 4 }

// The identity (empty-range) value for a reduce op.
@ red_id i op → i {
    ? == op 1 { ^ 1 } {}  // product
    ? == op 2 { ^ 9223372036854775807 } {}  // min → +∞
    ? == op 3 { ^ - 0 9223372036854775807 } {}  // max → −∞
    ^ 0  // sum, count
}

// Fold one mapped value into the accumulator (per element).
@ red_fold i op i acc i v → i {
    ? == op 0 { ^ + acc v } {}  // sum
    ? == op 1 { ^ * acc v } {}  // product
    ? == op 2 { ^ ? < v acc v acc } {}  // min
    ? == op 3 { ^ ? > v acc v acc } {}  // max
    ? == op 4 { ^ ? != v 0 + acc 1 acc } {}  // count of truthy
    ^ acc
}

// Combine two partial folds (across chunks). count combines by summing the
// per-chunk counts; every other op combines like its element fold.
@ red_combine i op i a i b → i {
    ? == op 4 { ^ + a b } {}
    ^ ( red_fold op a b )
}

// ── chunk + result codec ─────────────────────────────────────────

@ chunk_payload i op i lo i hi ( Vec u ) expr → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u op )
    ( bytes_push_u64_be b # u64 lo )
    ( bytes_push_u64_be b # u64 hi )
    ( vec_extend [u] b expr )
    ^ b
}

@ result_encode i value → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( bytes_push_u64_be b # u64 value )
    ^ b
}

@ result_decode ( Vec u ) p → i { ^ ?? ( bytes_read_u64_be p 0 ) { T x → # i x F → 0 } }

// ── the generic kernel handler (opaque bytes → bytes) ────────────
// Parses [op][lo][hi][expr], evaluates the kernel over [lo,hi), folds. A
// malformed kernel yields the reduce identity (a no-op partial) rather than a
// crash, so one bad task can't take a worker down.

@ kernel_handler → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : i op ?? ( vec_get [u] p 0 ) { T x → # i x F → 0 }
        : i lo ?? ( bytes_read_u64_be p 1 ) { T x → # i x F → 0 }
        : i hi ?? ( bytes_read_u64_be p 9 ) { T x → # i x F → 0 }
        : ( Vec u ) src ( bytes_slice p 17 ( vec_len [u] p ) )
        : *EParser ep # *EParser ( nurl_alloc Z EParser )
        : i root ( expr_parse src ep )
        : ~ i acc ( red_id op )
        ? . ep ok {
            : ~ i xx lo
            ~ < xx hi { = acc ( red_fold op acc ( expr_eval ep root xx ) ) = xx + xx 1 }
        } {}
        ( eparser_free ep )
        ( vec_free [u] src )
        ^ ( result_encode acc )
    }
}

// ── sharding: split [lo, hi) into n contiguous chunks ─────────────

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

// A ring key for chunk index i: distinct chunks hash to distinct ring points.
@ chunk_key i idx → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( bytes_push_u64_be b # u64 idx )
    ^ b
}

// True for a recognised reduce-op name; sets *op. Keeps the MCP layer thin.
@ reduce_op_of s name i fallback → i {
    ? != 0 ( nurl_str_eq name `sum` ) { ^ 0 } {}
    ? != 0 ( nurl_str_eq name `product` ) { ^ 1 } {}
    ? != 0 ( nurl_str_eq name `min` ) { ^ 2 } {}
    ? != 0 ( nurl_str_eq name `max` ) { ^ 3 } {}
    ? != 0 ( nurl_str_eq name `count` ) { ^ 4 } {}
    ^ fallback
}

@ reduce_op_name i op → s {
    ? == op 1 { ^ `product` } {}
    ? == op 2 { ^ `min` } {}
    ? == op 3 { ^ `max` } {}
    ? == op 4 { ^ `count` } {}
    ^ `sum`
}
