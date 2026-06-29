// packages/swarm-mcp/src/work.nu — the distributed map-reduce the cluster runs.
//
// A task is: evaluate an expression kernel (expr.nu) over an integer range
// [lo, hi) and fold the results with a reduce op. The coordinator shards the
// range; dist/ring routes each chunk to its owning worker; the worker parses
// the kernel once and folds it over its sub-range; the coordinator combines the
// partial folds. Every reduce op is associative, so sharding is exact.
//
//   reduce op : 0 sum · 1 product · 2 min · 3 max · 4 count (of truthy map)
//   dtype     : 0 int (i64) · 1 float (f64)
//   chunk     : [op:1][dtype:1][lo:8 BE][hi:8 BE][expr bytes…]
//   result    : [value:8 BE]  — i64, or an f64 bit pattern when dtype=float
//
// Float tasks fold in f64 over the same integer range (x is the index cast to
// double) and ship the partial as its f64 bit pattern through the same 8-byte
// result codec; the coordinator reinterprets it (see main.nu tids_combine).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `expr.nu`
$ `token.nu`

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

// ── float (f64) reduce — the dtype=1 dual of the three above ──────
// +∞ / −∞ identities for min/max come from their f64 bit patterns (0x7FF0…/
// 0xFFF0… = ±(2⁶³−2⁵²) signed): coordination-free and exact.

@ red_id_f i op → f {
    ? == op 1 { ^ 1.0 } {}                                  // product
    ? == op 2 { ^ ( bits_to_f64 9218868437227405312 ) } {}  // min → +∞
    ? == op 3 { ^ ( bits_to_f64 -4503599627370496 ) } {}    // max → −∞
    ^ 0.0  // sum, count
}

@ red_fold_f i op f acc f v → f {
    ? == op 0 { ^ + acc v } {}                       // sum
    ? == op 1 { ^ * acc v } {}                       // product
    ? == op 2 { ^ ? < v acc v acc } {}               // min
    ? == op 3 { ^ ? > v acc v acc } {}               // max
    ? == op 4 { ^ ? != v 0.0 + acc 1.0 acc } {}      // count of truthy
    ^ acc
}

@ red_combine_f i op f a f b → f {
    ? == op 4 { ^ + a b } {}
    ^ ( red_fold_f op a b )
}

// ── chunk + result codec ─────────────────────────────────────────

@ chunk_payload i op i dtype i lo i hi ( Vec u ) expr → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u op )
    ( vec_push [u] b # u dtype )
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
// The chunk payload arrives HMAC-tagged (token authenticity). The handler
// verifies the tag, parses [op][lo][hi][expr], evaluates the kernel over
// [lo,hi), folds, and returns the partial HMAC-tagged for the coordinator. A
// payload that fails the tag check (a stranger without the cluster token, or a
// corrupted frame) yields a tagged zero partial — never a crash, so one bad or
// hostile task can't take a worker down. A malformed-but-authentic kernel folds
// to the reduce identity for the same reason.
//
// `key` is the cluster HMAC key (token_key), captured by the handler closure.

@ kernel_handler ( Vec u ) key → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        ?? ( token_untag key p ) {
            F → {
                : ( Vec u ) z ( result_encode 0 )
                : ( Vec u ) out ( token_tag key z )
                ( vec_free [u] z )
                ^ out
            }
            T body → {
                : i op ?? ( vec_get [u] body 0 ) { T x → # i x F → 0 }
                : i dtype ?? ( vec_get [u] body 1 ) { T x → # i x F → 0 }
                : i lo ?? ( bytes_read_u64_be body 2 ) { T x → # i x F → 0 }
                : i hi ?? ( bytes_read_u64_be body 10 ) { T x → # i x F → 0 }
                : ( Vec u ) src ( bytes_slice body 18 ( vec_len [u] body ) )
                : *EParser ep # *EParser ( nurl_alloc Z EParser )
                : i root ( expr_parse src ep )
                : ~ i acc 0
                ? == dtype 1 {
                    // float (f64) fold: x is the integer index cast to double;
                    // the partial rides the wire as its f64 bit pattern.
                    : ~ f facc ( red_id_f op )
                    ? . ep ok {
                        : ~ i xx lo
                        ~ < xx hi { = facc ( red_fold_f op facc ( expr_eval_f ep root # f xx ) ) = xx + xx 1 }
                    } {}
                    = acc ( f64_to_bits facc )
                } {
                    = acc ( red_id op )
                    ? . ep ok {
                        : ~ i xx lo
                        ~ < xx hi { = acc ( red_fold op acc ( expr_eval ep root xx ) ) = xx + xx 1 }
                    } {}
                }
                ( eparser_free ep )
                ( vec_free [u] src )
                ( vec_free [u] body )
                : ( Vec u ) res ( result_encode acc )
                : ( Vec u ) out ( token_tag key res )
                ( vec_free [u] res )
                ^ out
            }
        }
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
