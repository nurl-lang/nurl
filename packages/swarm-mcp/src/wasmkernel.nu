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
//   chunk : [lo:8 BE][hi:8 BE][wasm module bytes…]   (the reduce op is baked
//           into the module by the wrapper, so the partial is final per chunk)
//
// The module is cached on each worker by a content hash, so re-running the same
// kernel (every chunk of a task, and across tasks) writes the .wasm only once.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`

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

// The worker handler for a wasm chunk: cache the module by hash, run it.
@ wasm_handler → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : i lo ?? ( bytes_read_u64_be p 0 ) { T x → # i x F → 0 }
        : i hi ?? ( bytes_read_u64_be p 8 ) { T x → # i x F → 0 }
        : ( Vec u ) wasm ( bytes_slice p 16 ( vec_len [u] p ) )
        : String hex ( __wasm_hash wasm )
        : String path ( __wasm_cache_path hex )
        ? ! ( file_exists ( string_data path ) ) {
            ?? ( write_file_bytes ( string_data path ) wasm ) { T _ → {} F _ → {} }
        } {}
        : i partial ( __wasm_run path lo hi )
        : ( Vec u ) r ( vec_new [u] )
        ( bytes_push_u64_be r # u64 partial )
        ( string_free hex ) ( string_free path ) ( vec_free [u] wasm )
        ^ r
    }
}
