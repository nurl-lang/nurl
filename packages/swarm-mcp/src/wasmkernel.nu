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
//   CPU chunk (kind_wasm)     : [lo:8 BE][hi:8 BE][wasm…]
//   GPU chunk (kind_wasm_gpu) : payload v2 — see wasm_gpu_chunk_payload below
//                               (adds an output mode, K, and runtime params)
//
// The reduce op is baked into the module by the wrapper, so the partial is
// final per chunk. A scalar module prints its partial as a decimal integer on
// stdout; for a float task that integer is the partial's f64 BIT PATTERN (see
// buildwasm.nu), so the same int wire carries it unchanged — the coordinator
// reinterprets it. Vector modes (sample/hist) write raw little-endian f64s to
// a worker-named output file instead (fast: one fwrite, no per-value stdout).
//
// The module is cached on each worker by a content hash, so re-running the same
// kernel (every chunk of a task, and across tasks — runtime params don't touch
// the module) writes the .wasm only once.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/random.nu`
$ `stdlib/ext/env.nu`
$ `token.nu`

@ kind_wasm → i { ^ 2 }

// GPU wasm chunks are a SEPARATE job kind, routed on the GPU capability ring
// (dist/job job_set_ring): only --gpu workers own these keys, and only they
// register this handler — a non-GPU worker can never receive (or garble) one.
@ kind_wasm_gpu → i { ^ 3 }

// GPU task output modes (baked into the generated program AND carried in the
// chunk so the worker knows how to invoke the module and collect its output).
@ gpu_mode_scalar → i { ^ 0 }  // partial's f64 bits on stdout
@ gpu_mode_sample → i { ^ 1 }  // hi-lo doubles written to an output file
@ gpu_mode_hist → i { ^ 2 }  // K bin sums written to an output file
@ gpu_mode_vecreduce → i { ^ 3 }  // K-vector scatter-add (gradient), K doubles to a file
@ gpu_mode_shuffle_map → i { ^ 4 }  // (key,value) per element: 16 bytes/elem to a file
@ gpu_mode_shuffle_reduce → i { ^ 5 }  // GPU combiner: chunk reduced by key into a K-slot table (16 bytes/slot: i64 key, f64 val) to a file

// Dataset storage-type codes (shared by the worker and the generator). A
// dataset element is stored in its native width and promoted to a double on the
// GPU. Defined here (the lowest shared module) so both wasmkernel and cudakernel
// see them. Code 1 = f64 keeps the original single-width behaviour.
@ data_dtype_f64 → i { ^ 1 }

@ data_dtype_f32 → i { ^ 2 }

@ data_dtype_i32 → i { ^ 3 }

@ data_dtype_i64 → i { ^ 4 }

@ data_dtype_esz i dtype → i {
    ? == dtype 2 { ^ 4 } {}
    ? == dtype 3 { ^ 4 } {}
    ^ 8
}

@ wasm_chunk_payload i lo i hi ( Vec u ) wasm → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( bytes_push_u64_be b # u64 lo )
    ( bytes_push_u64_be b # u64 hi )
    ( vec_extend [u] b wasm )
    ^ b
}

// ── GPU chunk payload (v2 / v3) ──────────────────────────────────
//   v2: [2][mode:1][lo:8][hi:8][K:4][nparams:2][f64 bits:8×n][wasm…]
//   v3: [3][mode:1][lo:8][hi:8][K:4][nparams:2][f64 bits:8×n]
//       [dlen:4][data slice: raw LE f64s][wasm…]
// mode selects the module's output contract; K is the histogram bin count
// (0 otherwise); params are runtime kernel arguments passed on the module's
// argv as f64-bit-pattern decimals — the SAME module (same content hash, no
// rebuild, warm worker cache) serves any parameter values. v3 additionally
// carries the chunk's DATASET SLICE — data[lo..hi) as raw doubles, following
// the map-reduce rule that a split travels with its task. dlen is exact
// (8·(hi−lo)) so a truncated frame is rejected, and dlen=0 means "no data"
// (the encoder then emits plain v2).
@ wasm_gpu_chunk_payload i mode i lo i hi i kbins ( Vec i ) params ( Vec u ) data ( Vec u ) wasm → ( Vec u ) {
    : i dlen ( vec_len [u] data )
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u ? > dlen 0 3 2 )
    ( vec_push [u] b # u mode )
    ( bytes_push_u64_be b # u64 lo )
    ( bytes_push_u64_be b # u64 hi )
    ( bytes_push_u32_be b # u32 kbins )
    : i np ( vec_len [i] params )
    ( bytes_push_u16_be b # u16 np )
    : ~ i k 0
    ~ < k np {
        ( bytes_push_u64_be b # u64 ?? ( vec_get [i] params k ) { T x → x F → 0 } )
        = k + k 1
    }
    ? > dlen 0 {
        ( bytes_push_u32_be b # u32 dlen )
        ( vec_extend [u] b data )
    } {}
    ( vec_extend [u] b wasm )
    ^ b
}

// v4: the chunk references its dataset blocks by CONTENT HASH instead of
// carrying the slice —
//   [4][mode:1][lo:8][hi:8][K:4][nparams:2][f64 bits:8×n]
//   [b0:4][nblob:2][hash32 × nblob][wasm…]
// b0 is the absolute index of the first referenced block on the dataset's
// block grid (blob.nu); the worker assembles data[lo..hi) from its block
// cache (seeded via kind_blob) and FAILS the chunk on any missing block.
@ wasm_gpu_chunk_payload_blobs i mode i lo i hi i kbins ( Vec i ) params i b0 i dtype ( Vec ( Vec u ) ) hashes ( Vec u ) wasm → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b 4 )
    // byte 1: mode in the low nibble, dataset dtype in the high nibble
    ( vec_push [u] b # u | & mode 15 << & dtype 15 4 )
    ( bytes_push_u64_be b # u64 lo )
    ( bytes_push_u64_be b # u64 hi )
    ( bytes_push_u32_be b # u32 kbins )
    : i np ( vec_len [i] params )
    ( bytes_push_u16_be b # u16 np )
    : ~ i k 0
    ~ < k np {
        ( bytes_push_u64_be b # u64 ?? ( vec_get [i] params k ) { T x → x F → 0 } )
        = k + k 1
    }
    ( bytes_push_u32_be b # u32 b0 )
    : i nb ( vec_len [( Vec u )] hashes )
    ( bytes_push_u16_be b # u16 nb )
    = k 0
    ~ < k nb {
        ?? ( vec_get [( Vec u )] hashes k ) { T h → { ( vec_extend [u] b h ) } F → {} }
        = k + k 1
    }
    ( vec_extend [u] b wasm )
    ^ b
}

: GpuChunk {
    i ok
    i mode
    i lo
    i hi
    i kbins
    ( Vec i ) params
    ( Vec u ) data  // raw LE f64 slice (empty without a dataset)
    i b0  // v4: first referenced block index on the dataset grid
    i dtype  // v4: storage type code (1 f64 · 2 f32 · 3 i32 · 4 i64)
    ( Vec ( Vec u ) ) blobs  // v4: 32-byte block hashes (empty otherwise)
    ( Vec u ) wasm
}

@ gpu_chunk_free GpuChunk c → v {
    ( vec_free [i] . c params )
    ( vec_free [u] . c data )
    ( blob_manifest_free . c blobs )
    ( vec_free [u] . c wasm )
}

@ wasm_gpu_chunk_decode ( Vec u ) body → GpuChunk {
    : ( Vec i ) params ( vec_new [i] )
    : ~ i ok 0
    : ~ i mode 0
    : ~ i lo 0
    : ~ i hi 0
    : ~ i kbins 0
    : ~ i b0 0
    : ~ i dtype 1
    : ~ ( Vec ( Vec u ) ) blobs ( vec_new [( Vec u )] )
    : ~ ( Vec u ) data ( vec_new [u] )
    : ~ ( Vec u ) wasm ( vec_new [u] )
    : i ver ?? ( vec_get [u] body 0 ) { T x → # i x F → 0 }
    ? == ver 4 {
        // byte 1 packs mode (low nibble) and the dataset dtype (high nibble)
        : i raw ?? ( vec_get [u] body 1 ) { T x → # i x F → 0 }
        = mode & raw 15
        : i dt >> raw 4
        = dtype ? > dt 0 dt 1
        = lo ?? ( bytes_read_u64_be body 2 ) { T x → # i x F → 0 }
        = hi ?? ( bytes_read_u64_be body 10 ) { T x → # i x F → 0 }
        = kbins ?? ( bytes_read_u32_be body 18 ) { T x → # i x F → 0 }
        : i np ?? ( bytes_read_u16_be body 22 ) { T x → # i x F → 0 }
        : i pend + 24 * np 8
        ? <= + pend 6 ( vec_len [u] body ) {
            = b0 ?? ( bytes_read_u32_be body pend ) { T x → # i x F → 0 }
            : i nb ?? ( bytes_read_u16_be body + pend 4 ) { T x → # i x F → 0 }
            : i hstart + pend 6
            : i hend + hstart * nb 32
            ? & > nb 0 <= hend ( vec_len [u] body ) {
                : ~ i k 0
                ~ < k np {
                    ( vec_push [i] params ?? ( bytes_read_u64_be body + 24 * k 8 ) { T x → x F → 0 } )
                    = k + k 1
                }
                = k 0
                ~ < k nb {
                    ( vec_push [( Vec u )] blobs ( bytes_slice body + hstart * k 32 + hstart * + k 1 32 ) )
                    = k + k 1
                }
                ( vec_free [u] wasm )
                = wasm ( bytes_slice body hend ( vec_len [u] body ) )
                = ok 1
            } {}
        } {}
    } {}
    ? | == ver 2 == ver 3 {
        = mode ?? ( vec_get [u] body 1 ) { T x → # i x F → 0 }
        = lo ?? ( bytes_read_u64_be body 2 ) { T x → # i x F → 0 }
        = hi ?? ( bytes_read_u64_be body 10 ) { T x → # i x F → 0 }
        = kbins ?? ( bytes_read_u32_be body 18 ) { T x → # i x F → 0 }
        : i np ?? ( bytes_read_u16_be body 22 ) { T x → # i x F → 0 }
        : i pend + 24 * np 8
        : ~ i dstart pend
        : ~ i dlen 0
        : ~ b sane <= pend ( vec_len [u] body )
        ? & sane == ver 3 {
            = dlen ?? ( bytes_read_u32_be body pend ) { T x → # i x F → -1 }
            = dstart + pend 4
            // the slice must be whole f64s covering exactly [lo, hi)
            = sane & & >= dlen 0 == dlen * 8 - hi lo <= + dstart dlen ( vec_len [u] body )
        } {}
        ? sane {
            : ~ i k 0
            ~ < k np {
                ( vec_push [i] params ?? ( bytes_read_u64_be body + 24 * k 8 ) { T x → x F → 0 } )
                = k + k 1
            }
            ? > dlen 0 {
                ( vec_free [u] data )
                = data ( bytes_slice body dstart + dstart dlen )
            } {}
            ( vec_free [u] wasm )
            = wasm ( bytes_slice body + dstart dlen ( vec_len [u] body ) )
            = ok 1
        } {}
    } {}
    ^ @ GpuChunk { ok mode lo hi kbins params data b0 dtype blobs wasm }
}

// v4: assemble data[lo..hi) into c.data from the content-addressed block
// cache. A v2/v3 chunk (no blob references) is a no-op T. F on ANY missing
// or corrupt block, or a reference window that does not cover the range —
// the caller fails the chunk VISIBLY instead of computing on garbage.
@ gpu_chunk_assemble inout GpuChunk c → b {
    : i nb ( vec_len [( Vec u )] . c blobs )
    ? > nb 0 {} { ^ T }
    ? == . c ok 1 {} { ^ F }
    : ( Vec u ) whole ( vec_new [u] )
    : ~ b bok T
    : ~ i bi 0
    ~ & bok < bi nb {
        ?? ( vec_get [( Vec u )] . c blobs bi ) {
            T h → { ? ( blob_append h whole ) {} { = bok F } }
            F → { = bok F }
        }
        = bi + bi 1
    }
    // Byte window of [lo, hi) inside the assembled blocks. Block b0 starts at
    // byte b0·(1 MiB) = b0·blob_block_vals·8; each element occupies esz bytes.
    : i esz ( data_dtype_esz . c dtype )
    : i skip - * . c lo esz * . c b0 * ( blob_block_vals ) 8
    : i take * - . c hi . c lo esz
    ? & bok & >= skip 0 <= + skip take ( vec_len [u] whole ) {
        ( vec_free [u] . c data )
        = . c data ( bytes_slice whole skip + skip take )
    } { = bok F }
    ( vec_free [u] whole )
    ^ bok
}

// FNV-1a/64 content hash → 16 lowercase hex chars, for the cache filename.
@ _wasm_hash ( Vec u ) v → String {
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
    // env_var_or returns an OWNED String — grow it in place (string_concat
    // BORROWS its args, so the `/swarmc_` temporary used to leak per call)
    : String p ( env_var_or `TMPDIR` `/tmp` )
    ( string_push_str p `/swarmc_` )
    ( string_push_str p ( string_data hex ) )
    ( string_push_str p `.wasm` )
    ^ p
}

// The runtime binary: $WASMTIME, else `wasmtime` on PATH. The pure-NURL
// packages/wasmtime is a drop-in here (no external dependency); the
// Bytecode-Alliance wasmtime works equally well.
@ __wasmtime → String { ^ ( env_var_or `WASMTIME` `wasmtime` ) }

// Run a cached module over [lo, hi). ok=1 iff the runtime ran the module to a
// zero exit — a failed chunk (missing wasmtime, module trap, GPU error path
// exiting non-zero) is REPORTED, not folded into the reduce as a silent zero.
// allow_gpu≠0 passes --allow-gpu so the module's env imports (CUDA/NVRTC)
// resolve to real hardware — this needs the pure-NURL packages/wasmtime.
: WasmRun { i ok i value }

@ __wasm_run String path i lo i hi i allow_gpu → WasmRun {
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `run` )
    ? != allow_gpu 0 { ( vec_push [s] args `--allow-gpu` ) } {}
    ( vec_push [s] args ( string_data path ) )
    : s los ( nurl_str_int lo )
    : s his ( nurl_str_int hi )
    ( vec_push [s] args los )
    ( vec_push [s] args his )
    : String wt ( __wasmtime )
    : ~ i v 0
    : ~ i ok 0
    ?? ( process_run ( string_data wt ) args `` ) {
        T out → { ? == ( output_exit_code out ) 0 { = ok 1 = v ( nurl_str_to_int ( output_stdout out ) ) } {} ( output_free out ) }
        F e → {}
    }
    ( string_free wt )
    ( vec_free [s] args )
    ^ @ WasmRun { ok v }
}

// The worker handler for a (CPU) wasm chunk: verify the cluster HMAC tag,
// cache the module by content hash, run it under wasmtime, return the partial
// tagged for the coordinator. An untrusted/forged payload yields a tagged
// ok=0 — a stranger can't make a worker fetch-and-run an arbitrary module.
// `key` is the cluster HMAC key (token_key), captured by the handler closure.
@ wasm_handler ( Vec u ) key → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : ~ i partial 0
        : ~ i run_ok 0
        ?? ( token_untag key p ) {
            F → {}
            T body → {
                : i lo ?? ( bytes_read_u64_be body 0 ) { T x → # i x F → 0 }
                : i hi ?? ( bytes_read_u64_be body 8 ) { T x → # i x F → 0 }
                : ( Vec u ) wasm ( bytes_slice body 16 ( vec_len [u] body ) )
                : String hex ( _wasm_hash wasm )
                : String path ( __wasm_cache_path hex )
                ? ! ( file_exists ( string_data path ) ) {
                    ?? ( write_file_bytes ( string_data path ) wasm ) { T _ → {} F _ → {} }
                } {}
                : WasmRun wr ( __wasm_run path lo hi 0 )
                = run_ok . wr ok
                = partial . wr value
                ( string_free hex ) ( string_free path ) ( vec_free [u] wasm )
                ( vec_free [u] body )
            }
        }
        // result wire: [ok:1][partial:8] — the coordinator counts failed
        // chunks and marks the task instead of silently reducing zeros.
        // (An untagged/forged payload reports ok=0 too.)
        : ( Vec u ) r ( vec_new [u] )
        ( vec_push [u] r # u run_ok )
        ( bytes_push_u64_be r # u64 partial )
        : ( Vec u ) out ( token_tag key r )
        ( vec_free [u] r )
        ^ out
    }
}

// ── the GPU chunk handler (payload v2, all output modes) ─────────

// 16 lowercase hex chars of an i64 (unique temp-file names).
@ __hex_u64 i h → String {
    : String out ( string_with_cap 16 )
    : ~ i i 60
    ~ >= i 0 {
        : i nib & >> h i 15
        ( string_push_char out ? < nib 10 + 48 nib + 87 nib )
        = i - i 4
    }
    ^ out
}

: GpuOut { i ok i scalar ( Vec u ) bytes }

// Run a cached module for one GPU chunk under `wt run --allow-gpu`.
// Scalar mode: the partial's f64 bits on stdout (as before). Sample/hist
// modes: the module writes raw LITTLE-ENDIAN f64s to an output file the
// worker names under $TMPDIR (preopened into the sandbox via --dir); the
// exact byte length is validated (8·(hi−lo), or 8·K for a histogram).
// Runtime params ride argv as f64-bit-pattern decimals.
@ __wasm_run_gpu String path GpuChunk c → GpuOut {
    : String tmp ( env_var_or `TMPDIR` `/tmp` )
    : b vecmode | | | == . c mode ( gpu_mode_sample ) == . c mode ( gpu_mode_shuffle_map ) == . c mode ( gpu_mode_shuffle_reduce ) | == . c mode ( gpu_mode_hist ) == . c mode ( gpu_mode_vecreduce )
    : b hasdata > ( vec_len [u] . c data ) 0
    : ~ String outp ( string_new )
    ? vecmode {
        ( string_push_str outp ( string_data tmp ) )
        ( string_push_str outp `/swarmo_` )
        : String rh ( __hex_u64 ( rand_u64 ) )
        ( string_push_str outp ( string_data rh ) )
        ( string_free rh )
        ( string_push_str outp `.bin` )
    } {}
    // the chunk's dataset slice → a temp in-file the module reads back
    : ~ String inp ( string_new )
    : ~ b inp_ok T
    ? hasdata {
        ( string_push_str inp ( string_data tmp ) )
        ( string_push_str inp `/swarmi_` )
        : String rh2 ( __hex_u64 ( rand_u64 ) )
        ( string_push_str inp ( string_data rh2 ) )
        ( string_free rh2 )
        ( string_push_str inp `.bin` )
        ?? ( write_file_bytes ( string_data inp ) . c data ) { T _ → {} F e → { = inp_ok F } }
    } {}
    // The numeric argv strings (lo, hi, K, params…) are variable-count and
    // built in loops — a `: s` binding would be auto-reclaimed at its block's
    // end, BEFORE process_run reads it. So they live in ONE owned arena
    // String as NUL-separated segments; the args vec gets pointer views into
    // it, resolved only after the arena stops growing (pushes may realloc).
    : String blob ( string_new )
    : ( Vec i ) offs ( vec_new [i] )
    ( vec_push [i] offs ( string_len blob ) )
    ( string_push_str blob ( nurl_str_int . c lo ) ) ( string_push_char blob 0 )
    ( vec_push [i] offs ( string_len blob ) )
    ( string_push_str blob ( nurl_str_int . c hi ) ) ( string_push_char blob 0 )
    // hist, vecreduce AND shuffle_reduce carry K (bin count / gradient dim /
    // hash-table slots) in argv
    ? | | == . c mode ( gpu_mode_hist ) == . c mode ( gpu_mode_vecreduce ) == . c mode ( gpu_mode_shuffle_reduce ) {
        ( vec_push [i] offs ( string_len blob ) )
        ( string_push_str blob ( nurl_str_int . c kbins ) ) ( string_push_char blob 0 )
    } {}
    : i np ( vec_len [i] . c params )
    : ~ i k 0
    ~ < k np {
        ( vec_push [i] offs ( string_len blob ) )
        ( string_push_str blob ( nurl_str_int ?? ( vec_get [i] . c params k ) { T x → x F → 0 } ) )
        ( string_push_char blob 0 )
        = k + k 1
    }
    : i base # i ( string_data blob )
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `run` )
    ( vec_push [s] args `--allow-gpu` )
    ? | vecmode hasdata { ( vec_push [s] args `--dir` ) ( vec_push [s] args ( string_data tmp ) ) } {}
    ( vec_push [s] args ( string_data path ) )
    ( vec_push [s] args # s + base ?? ( vec_get [i] offs 0 ) { T x → x F → 0 } )
    ( vec_push [s] args # s + base ?? ( vec_get [i] offs 1 ) { T x → x F → 0 } )
    ? hasdata { ( vec_push [s] args ( string_data inp ) ) } {}
    ? vecmode { ( vec_push [s] args ( string_data outp ) ) } {}
    : i ntail - ( vec_len [i] offs ) 2
    : ~ i t 0
    ~ < t ntail {
        ( vec_push [s] args # s + base ?? ( vec_get [i] offs + 2 t ) { T x → x F → 0 } )
        = t + t 1
    }
    : String wt ( __wasmtime )
    : ~ i ok 0
    : ~ i scalar 0
    : ~ ( Vec u ) outb ( vec_new [u] )
    ? ! inp_ok { ( string_free wt ) ( vec_free [s] args ) ( vec_free [i] offs ) ( string_free blob ) ( string_free inp ) ( string_free outp ) ( string_free tmp ) ^ @ GpuOut { 0 0 outb } } {}
    ?? ( process_run ( string_data wt ) args `` ) {
        T out → {
            ? == ( output_exit_code out ) 0 {
                ? vecmode {
                    ?? ( read_file_bytes ( string_data outp ) ) {
                        T bts → {
                            : i want ? == . c mode ( gpu_mode_shuffle_reduce ) * 16 + . c kbins 1 ? == . c mode ( gpu_mode_shuffle_map ) * 16 - . c hi . c lo * 8 ? | == . c mode ( gpu_mode_hist ) == . c mode ( gpu_mode_vecreduce ) . c kbins - . c hi . c lo
                            ? == ( vec_len [u] bts ) want {
                                ( vec_free [u] outb )
                                = outb bts
                                = ok 1
                            } { ( vec_free [u] bts ) }
                        }
                        F e → {}
                    }
                } {
                    = ok 1
                    = scalar ( nurl_str_to_int ( output_stdout out ) )
                }
            } {}
            ( output_free out )
        }
        F e → {}
    }
    ? vecmode { ?? ( file_delete ( string_data outp ) ) { T _ → {} F _ → {} } } {}
    ? hasdata { ?? ( file_delete ( string_data inp ) ) { T _ → {} F _ → {} } } {}
    ( vec_free [s] args ) ( vec_free [i] offs )
    ( string_free blob ) ( string_free inp ) ( string_free outp ) ( string_free wt ) ( string_free tmp )
    ^ @ GpuOut { ok scalar outb }
}

// GPU worker handler: decode payload v2, cache the module, run per mode, and
// reply the mode's result frame — scalar [ok:1][bits:8], vector
// [ok:1][count:4 BE][f64 LE × count]. Forged/undecodable payloads → ok=0.
@ wasm_gpu_handler ( Vec u ) key → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : ~ i run_ok 0
        : ~ i scalar 0
        : ~ i mode ( gpu_mode_scalar )
        : ~ ( Vec u ) outb ( vec_new [u] )
        ?? ( token_untag key p ) {
            F → {}
            T body → {
                : ~ GpuChunk c ( wasm_gpu_chunk_decode body )
                = mode . c mode
                ? ( gpu_chunk_assemble c ) {} { = . c ok 0 }
                ? == . c ok 1 {
                    : String hex ( _wasm_hash . c wasm )
                    : String path ( __wasm_cache_path hex )
                    ? ! ( file_exists ( string_data path ) ) {
                        ?? ( write_file_bytes ( string_data path ) . c wasm ) { T _ → {} F _ → {} }
                    } {}
                    : GpuOut r ( __wasm_run_gpu path c )
                    = run_ok . r ok
                    = scalar . r scalar
                    ( vec_free [u] outb )
                    = outb . r bytes
                    ( string_free hex ) ( string_free path )
                } {}
                ( gpu_chunk_free c )
                ( vec_free [u] body )
            }
        }
        : ( Vec u ) r ( vec_new [u] )
        ( vec_push [u] r # u run_ok )
        ? == mode ( gpu_mode_scalar ) {
            ( bytes_push_u64_be r # u64 scalar )
        } {
            ( bytes_push_u32_be r # u32 / ( vec_len [u] outb ) 8 )
            ( vec_extend [u] r outb )
        }
        ( vec_free [u] outb )
        : ( Vec u ) out ( token_tag key r )
        ( vec_free [u] r )
        ^ out
    }
}
