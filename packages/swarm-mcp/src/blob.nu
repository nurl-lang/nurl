// packages/swarm-mcp/src/blob.nu — content-addressed dataset blocks.
//
// The v3 payload shipped each chunk's dataset slice INSIDE every task, so
// N submits (or N iteration rounds) over the same data paid the transfer
// N times. This layer makes data transfer content-addressed and one-shot:
//
//   * a dataset is cut on a FIXED absolute grid of blocks
//     (BLOB_BLOCK_VALS f64 values = 1 MiB; the last block may be short);
//     each block is keyed by its BLAKE3-256 (stdlib/std/hash_blake3.nu),
//   * a worker caches blocks on disk ($TMPDIR/swarmb_<hex>.blob), verified
//     against the hash on arrival — a re-submit or the next iteration
//     round references the same hashes and moves NO data,
//   * blocks are SEEDED through the ordinary job machinery: a kind_blob
//     task with the SAME ring key as the compute chunk that needs the
//     block lands on the same worker (consistent hash: same ring + same
//     key → same owner). No new transport protocol, no pull-request
//     re-entrancy — and the cluster HMAC token authenticates blocks
//     exactly like every other payload.
//
// A compute chunk then references its blocks by hash (payload v4, see
// wasmkernel.nu) and the worker assembles the slice from its cache; a
// missing or corrupt block fails the chunk VISIBLY (ok=0 → failed_chunks),
// never silently.
//
// NOTE: siblings are imported by the consumer in dependency order
// (main.nu: token.nu → blob.nu → …); this file uses token_tag/token_untag
// from token.nu without importing it, like the other kernel files.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/hash_blake3.nu`
$ `stdlib/ext/env.nu`

// The absolute block grid: block b covers dataset values
// [b·BLOB_BLOCK_VALS, (b+1)·BLOB_BLOCK_VALS).
@ blob_block_vals → i { ^ 131072 }  // 1 MiB of f64s — the transfer unit (a
// larger single frame is fragile through a blocking relay client; 1 MiB
// matches the wasm-module size that reliably traverses the relay)

// Job kind for a block-seed task (kernel=1, wasm=2, wasm_gpu=3).
@ kind_blob → i { ^ 4 }

@ blob_hash ( Vec u ) bytes → ( Vec u ) { ^ ( blake3_pure bytes ) }

@ blob_hex ( Vec u ) h → String {
    : i n ( vec_len [u] h )
    : String out ( string_with_cap * n 2 )
    : ~ i k 0
    ~ < k n {
        : i b ?? ( vec_get [u] h k ) { T x → # i x F → 0 }
        : i hi >> b 4
        : i lo & b 15
        ( string_push_char out ? < hi 10 + 48 hi + 87 hi )
        ( string_push_char out ? < lo 10 + 48 lo + 87 lo )
        = k + k 1
    }
    ^ out
}

// Where this worker caches blocks: $TMPDIR (or /tmp) + /swarmb_<hex>.blob.
@ __blob_cache_path String hex → String {
    // env_var_or returns an OWNED String — grow it in place (string_concat
    // would BORROW its args and leak a temporary)
    : String p ( env_var_or `TMPDIR` `/tmp` )
    ( string_push_str p `/swarmb_` )
    ( string_push_str p ( string_data hex ) )
    ( string_push_str p `.blob` )
    ^ p
}

@ blob_cached ( Vec u ) hash → b {
    : String hex ( blob_hex hash )
    : String p ( __blob_cache_path hex )
    : b have ( file_exists ( string_data p ) )
    ( string_free hex )
    ( string_free p )
    ^ have
}

// Verify + store a block (idempotent: an already-cached hash is a no-op).
// F when the bytes do not hash to `hash` — a corrupt or forged block is
// never written under a name it doesn't own.
@ blob_store ( Vec u ) hash ( Vec u ) bytes → b {
    : ( Vec u ) real ( blob_hash bytes )
    : b match ( bytes_eq real hash )
    ( vec_free [u] real )
    ? match {} { ^ F }
    : String hex ( blob_hex hash )
    : String p ( __blob_cache_path hex )
    : ~ b okw T
    ? ( file_exists ( string_data p ) ) {} {
        ?? ( write_file_bytes ( string_data p ) bytes ) { T _ → {} F _ → { = okw F } }
    }
    ( string_free hex )
    ( string_free p )
    ^ okw
}

// Append the cached block `hash` to `out`. F on miss or a cache file that
// no longer matches its hash (deleted / truncated / tampered).
@ blob_append ( Vec u ) hash ( Vec u ) out → b {
    : String hex ( blob_hex hash )
    : String p ( __blob_cache_path hex )
    : ~ b okr F
    ?? ( read_file_bytes ( string_data p ) ) {
        T bytes → {
            : ( Vec u ) real ( blob_hash bytes )
            ? ( bytes_eq real hash ) {
                ( vec_extend [u] out bytes )
                = okr T
            } {}
            ( vec_free [u] real )
            ( vec_free [u] bytes )
        }
        F _ → {}
    }
    ( string_free hex )
    ( string_free p )
    ^ okr
}

// ── the seed task ────────────────────────────────────────────────────
// payload (inside the HMAC tag): [hash:32][block bytes]

@ blob_seed_payload ( Vec u ) hash ( Vec u ) bytes → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_extend [u] b hash )
    ( vec_extend [u] b bytes )
    ^ b
}

// Worker handler for kind_blob: authenticate, verify content address,
// cache. Result wire matches the scalar frame ([ok:1][0:8]) so the
// coordinator's readiness/failure accounting needs no special case.
@ blob_handler ( Vec u ) key → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : ~ i ok 0
        ?? ( token_untag key p ) {
            F → {}
            T body → {
                ? >= ( vec_len [u] body ) 33 {
                    : ( Vec u ) hash ( bytes_slice body 0 32 )
                    : ( Vec u ) bytes ( bytes_slice body 32 ( vec_len [u] body ) )
                    ? ( blob_store hash bytes ) { = ok 1 } {}
                    ( vec_free [u] hash )
                    ( vec_free [u] bytes )
                } {}
                ( vec_free [u] body )
            }
        }
        : ( Vec u ) r ( vec_new [u] )
        ( vec_push [u] r # u ok )
        ( bytes_push_u64_be r # u64 0 )
        : ( Vec u ) out ( token_tag key r )
        ( vec_free [u] r )
        ^ out
    }
}

// ── manifest: a dataset's block table ────────────────────────────────
// Hashes of every block on the absolute grid, in order. Block b's bytes
// are data[b·8·BV .. min(end, (b+1)·8·BV)).

@ blob_manifest ( Vec u ) data → ( Vec ( Vec u ) ) {
    : ( Vec ( Vec u ) ) out ( vec_new [( Vec u )] )
    : i n ( vec_len [u] data )
    : i bb * ( blob_block_vals ) 8
    : ~ i off 0
    ~ < off n {
        : i end ? < + off bb n { + off bb } { n }
        : ( Vec u ) block ( bytes_slice data off end )
        ( vec_push [( Vec u )] out ( blob_hash block ) )
        ( vec_free [u] block )
        = off end
    }
    ^ out
}

@ blob_manifest_free ( Vec ( Vec u ) ) m → v {
    : i n ( vec_len [( Vec u )] m )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [( Vec u )] m k ) { T h → { ( vec_free [u] h ) } F → {} }
        = k + k 1
    }
    ( vec_free [( Vec u )] m )
}
