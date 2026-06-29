// packages/swarm-mcp/src/wasmkernel.nu — phase 2: run a NURL-compiled wasm
// kernel over a chunk.
//
// The language model writes a kernel as ordinary NURL — anything, not just an
// expression — and compiles it (via the NURL build service) to a wasm32-wasi
// module whose `main` reads `lo hi` from argv, folds the kernel over [lo, hi),
// and prints the partial. The coordinator ships that module plus a sub-range to
// each worker; the worker runs it under `wasmtime` and returns the partial,
// which the coordinator combines with the reduce op exactly as in phase 1.
//
// The `wasmtime` here is just a CLI contract — `wasmtime run <module> <lo> <hi>`,
// partial on stdout. The toolchain's own pure-NURL runtime (packages/wasmtime)
// satisfies it exactly, so a worker needs NO external runtime: put that binary
// on PATH as `wasmtime`, or point $WASMTIME at it. The Bytecode-Alliance
// wasmtime works too — whichever $WASMTIME resolves to is used.
//
//   chunk : [lo:8 BE][hi:8 BE][wasm module bytes…]   (the reduce op is baked
//           into the module by the wrapper, so the partial is final per chunk)
//
// The module prints its partial as a decimal integer on stdout; __wasm_run reads
// it back with nurl_str_to_int. For a float task (dtype=1) the module prints the
// partial's f64 BIT PATTERN as that decimal integer (see buildwasm.nu), so the
// same int wire carries it unchanged — the coordinator reinterprets it in
// tids_combine's float path. This file is dtype-agnostic: it ships and runs the
// module and returns whatever integer it printed.
//
// The module is cached on each worker by a content hash, so re-running the same
// kernel (every chunk of a task, and across tasks) writes the .wasm only once.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`
$ `token.nu`

@ kind_wasm → i { ^ 2 }

@ wasm_chunk_payload i lo i hi ( Vec u ) wasm → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( bytes_push_u64_be b # u64 lo )
    ( bytes_push_u64_be b # u64 hi )
    ( vec_extend [u] b wasm )
    ^ b
}

// FNV-1a/64 content hash → 16 lowercase hex chars, for the cache filename.
@ __wasm_hash ( Vec u ) v → String {
    : ~ i h -3750763034362895579  // 14695981039346656037 as signed i64
    : i n ( vec_len [u] v )
    : ~ i k 0
    ~ < k n {
        : i b ?? ( vec_get [u] v k ) { T x → # i x F → 0 }
        = h ^^ h b
        = h * h 1099511628211
        = k + k 1
    }
    : String out ( string_with_cap 16 )
    : ~ i i 60
    ~ >= i 0 {
        : i nib & >> h i 15
        ( string_push_char out ? < nib 10 + 48 nib + 87 nib )
        = i - i 4
    }
    ^ out
}

// Where this worker caches modules: $TMPDIR (or /tmp) + /swarmc_<hash>.wasm.
@ __wasm_cache_path String hex → String {
    : String dir ( env_var_or `TMPDIR` `/tmp` )
    : String p ( string_concat dir ( string_from `/swarmc_` ) )
    ( string_free dir )
    ( string_push_str p ( string_data hex ) )
    ( string_push_str p `.wasm` )
    ^ p
}

// The runtime binary: $WASMTIME, else `wasmtime` on PATH. The pure-NURL
// packages/wasmtime is a drop-in here (no external dependency); the
// Bytecode-Alliance wasmtime works equally well.
@ __wasmtime → String { ^ ( env_var_or `WASMTIME` `wasmtime` ) }

// Run a cached module over [lo, hi); returns the printed partial (0 on any
// failure — a broken module can't take a worker down).
@ __wasm_run String path i lo i hi → i {
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `run` )
    ( vec_push [s] args ( string_data path ) )
    : s los ( nurl_str_int lo )
    : s his ( nurl_str_int hi )
    ( vec_push [s] args los )
    ( vec_push [s] args his )
    : String wt ( __wasmtime )
    : ~ i v 0
    ?? ( process_run ( string_data wt ) args `` ) {
        T out → { ? == ( output_exit_code out ) 0 { = v ( nurl_str_to_int ( output_stdout out ) ) } {} ( output_free out ) }
        F e → {}
    }
    ( string_free wt )
    ( vec_free [s] args )
    ^ v
}

// The worker handler for a wasm chunk: verify the cluster HMAC tag, cache the
// module by content hash, run it under wasmtime, return the partial tagged for
// the coordinator. An untrusted/forged payload yields a tagged zero — a
// stranger can't make a worker fetch-and-run an arbitrary module. `key` is the
// cluster HMAC key (token_key), captured by the handler closure.
@ wasm_handler ( Vec u ) key → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : ~ i partial 0
        : ~ b ok F
        ?? ( token_untag key p ) {
            F → {}
            T body → {
                = ok T
                : i lo ?? ( bytes_read_u64_be body 0 ) { T x → # i x F → 0 }
                : i hi ?? ( bytes_read_u64_be body 8 ) { T x → # i x F → 0 }
                : ( Vec u ) wasm ( bytes_slice body 16 ( vec_len [u] body ) )
                : String hex ( __wasm_hash wasm )
                : String path ( __wasm_cache_path hex )
                ? ! ( file_exists ( string_data path ) ) {
                    ?? ( write_file_bytes ( string_data path ) wasm ) { T _ → {} F _ → {} }
                } {}
                = partial ( __wasm_run path lo hi )
                ( string_free hex ) ( string_free path ) ( vec_free [u] wasm )
                ( vec_free [u] body )
            }
        }
        : ( Vec u ) r ( vec_new [u] )
        ( bytes_push_u64_be r # u64 partial )
        : ( Vec u ) out ( token_tag key r )
        ( vec_free [u] r )
        ^ out
    }
}
