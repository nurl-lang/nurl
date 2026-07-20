// packages/swarm-mcp/tests/cudakernel_test.nu — offline tests for the CUDA
// chunk-kernel generator (cudakernel.nu) and the wasm handler's [ok][value]
// result frame. No GPU needed: the generated program is only inspected as
// text here (the live path is exercised by tests/gpu_smoke.sh). Run from the
// package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/cudakernel_test.nu /tmp/ck && /tmp/ck

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `src/token.nu`
$ `src/blob.nu`
$ `src/cudakernel.nu`
$ `src/wasmkernel.nu`

@ pb s label b ok → v {
    ( nurl_print label ) ( nurl_print ? ok ` PASS\n` ` FAIL\n` )
}

@ has String hay s needle → b { ^ >= ( nurl_str_find ( string_data hay ) needle ) 0 }

@ main → i {
    // ── validation ────────────────────────────────────────────────
    ( pb `plain CUDA source accepted:      ` ( cuda_src_ok `__device__ double f(long long x) { return 1.0; }` ) )
    : String tick ( string_from `double f ` )
    ( string_push_char tick 96 )
    ( pb `backtick rejected:               ` ? ( cuda_src_ok ( string_data tick ) ) F T )
    ( string_free tick )

    // ── generated program shape (sum) ─────────────────────────────
    : String p ( cuda_wrap `__device__ double f(long long x) { return (double)x; }` 0 ( gpu_mode_scalar ) 0 0 )
    ( pb `program declares cuInit:         ` ( has p `@ cuInit i32 flags` ) )
    ( pb `program embeds swarm_map kernel: ` ( has p `swarm_map(long long lo, long long hi, double* out)` ) )
    ( pb `program has a main:              ` ( has p `@ main → i` ) )
    ( pb `sum combines with +:             ` ( has p `acc = acc + v` ) )
    ( pb `sum identity 0.0:                ` ( has p `double acc = 0.0` ) )
    ( pb `partial printed as f64 bits:     ` ( has p `f64_to_bits acc` ) )
    ( string_free p )

    // ── op splices ────────────────────────────────────────────────
    : String pmin ( cuda_wrap `__device__ double f(long long x) { return (double)x; }` 2 ( gpu_mode_scalar ) 0 0 )
    ( pb `min combines with fmin:          ` ( has pmin `fmin(acc, v)` ) )
    ( pb `min identity +inf (CUDA):        ` ( has pmin `(1.0/0.0)` ) )
    ( pb `min identity +inf (host bits):   ` ( has pmin `bits_to_f64 9218868437227405312` ) )
    ( string_free pmin )
    : String pcnt ( cuda_wrap `__device__ double f(long long x) { return (double)x; }` 4 ( gpu_mode_scalar ) 0 0 )
    ( pb `count maps truthiness to 1.0:    ` ( has pcnt `(f(x) != 0.0 ? 1.0 : 0.0)` ) )
    ( string_free pcnt )

    // ── mode + params splices ─────────────────────────────────────
    : String psam ( cuda_wrap `__device__ double f(long long x) { return (double)x; }` 0 ( gpu_mode_sample ) 0 0 )
    ( pb `sample kernel writes out[x-lo]:  ` ( has psam `out[x - lo] = f(x)` ) )
    ( pb `sample main takes an outpath:    ` ( has psam `nurl_argv_get 3` ) )
    ( pb `sample writes via fwrite:        ` ( has psam `fwrite # s host 1 obytes fh` ) )
    ( string_free psam )
    : String phist ( cuda_wrap `__device__ long long bin(long long x) { return x % 4; }` 0 ( gpu_mode_hist ) 0 0 )
    ( pb `hist default val emitted:        ` ( has phist `__device__ double val(long long x) { return 1.0; }` ) )
    ( pb `hist uses CAS atomic add:        ` ( has phist `atomicCAS(a, assumed,` ) )
    ( pb `hist guards the bucket range:    ` ( has phist `if (b >= 0 && b < K)` ) )
    ( pb `hist K rides argv:               ` ( has phist `nurl_argv_get 4` ) )
    ( string_free phist )
    : String phv ( cuda_wrap `__device__ long long bin(long long x) { return 0; } __device__ double val(long long x) { return 2.0; }` 0 ( gpu_mode_hist ) 0 0 )
    ( pb `user val suppresses the default: ` ? ( has phv `val(long long x) { return 1.0; }` ) F T )
    ( string_free phv )
    // ── vecreduce (gradient scatter-add) ──────────────────────────
    : String pvec ( cuda_wrap `__device__ void grad(long long x, double v, double* g, const double* p) { swarm_g_add(g, 0, 2.0 * (p[0] - v)); }` 0 ( gpu_mode_vecreduce ) 1 1 )
    ( pb `vecreduce forward-decls g_add:   ` ( has pvec `__device__ void swarm_g_add(double* g, long long j, double val);` ) )
    ( pb `vecreduce defines g_add helper:  ` ( has pvec `if (j >= 0 && j < __swK) swarm_atomic_add(&g[j], val)` ) )
    ( pb `vecreduce uses CAS atomic add:   ` ( has pvec `atomicCAS(a, assumed,` ) )
    ( pb `vecreduce kernel calls grad:     ` ( has pvec `grad(x, (double)in[x - lo], out, p)` ) )
    ( pb `vecreduce sets K for the guard:  ` ( has pvec `__swK = K;` ) )
    ( pb `vecreduce K rides argv:          ` ( has pvec `nurl_argv_get 5` ) )
    ( pb `vecreduce writes the K-vec file: ` ( has pvec `fwrite # s host 1 obytes fh` ) )
    ( string_free pvec )
    // ── update kernel (compute_iterate general step: sample over [0,S)) ──
    : String pupd ( cuda_wrap_update `__device__ double update(long long j, const double* p) { double s = swarm_acc(j); double n = swarm_acc(swarm_dim + j); return (n > 0.0) ? (s / n) : swarm_state(j); }` 2 4 )
    ( pb `update sets swarm_dim S=2:       ` ( has pupd `#define swarm_dim 2` ) )
    ( pb `update sets swarm_adim A=4:      ` ( has pupd `#define swarm_adim 4` ) )
    ( pb `update maps state accessor:      ` ( has pupd `#define swarm_state(i) (p[(i)])` ) )
    ( pb `update maps acc accessor:        ` ( has pupd `#define swarm_acc(i) (p[swarm_dim + (i)])` ) )
    ( pb `update maps N accessor:          ` ( has pupd `#define swarm_N (p[swarm_dim + swarm_adim])` ) )
    ( pb `update maps param accessor:      ` ( has pupd `#define swarm_param(i) (p[swarm_dim + swarm_adim + 1 + (i)])` ) )
    ( pb `update shims f from update:      ` ( has pupd `double f(long long x, const double* p) { return update(x, p); }` ) )
    ( pb `update rides sample kernel:      ` ( has pupd `out[x - lo] = f(x, p)` ) )
    ( pb `update takes p as a param:       ` ( has pupd `swarm_map(long long lo, long long hi, double* out, const double* p)` ) )
    ( pb `update main writes the file:     ` ( has pupd `fwrite # s host 1 obytes fh` ) )
    ( string_free pupd )
    // ── shuffle map (key, value) per element ──────────────────────
    : String psh ( cuda_wrap `__device__ long long key(long long x) { return x % 5; } __device__ double value(long long x) { return 1.0; }` 0 ( gpu_mode_shuffle_map ) 0 0 )
    ( pb `shuffle writes key as i64 slot:  ` ( has psh `long long* ok = (long long*)out;` ) )
    ( pb `shuffle stores key(...):          ` ( has psh `ok[2*(x - lo)] = key` ) )
    ( pb `shuffle stores value(...):        ` ( has psh `out[2*(x - lo) + 1] = value` ) )
    ( pb `shuffle out sized 16 bytes/elem:  ` ( has psh `: i obytes * - hi lo 16` ) )
    ( pb `shuffle writes the pair file:     ` ( has psh `fwrite # s host 1 obytes fh` ) )
    ( string_free psh )
    : String pshd ( cuda_wrap `__device__ long long key(long long x, double v) { return (long long)v; } __device__ double value(long long x, double v) { return v; }` 0 ( gpu_mode_shuffle_map ) 0 1 )
    ( pb `shuffle+data: key(x, in[x-lo]):   ` ( has pshd `key(x, (double)in[x - lo])` ) )
    ( string_free pshd )
    // ── shuffle reduce: the GPU combiner (per-chunk reduce-by-key) ─────
    : String prd ( cuda_wrap `__device__ long long key(long long x) { return x % 5; } __device__ double value(long long x) { return 1.0; }` 4 ( gpu_mode_shuffle_reduce ) 0 0 )
    ( pb `reduce: K-slot table sig (out,K):  ` ( has prd `double* out, long long K` ) )
    ( pb `reduce: reads key into slot array: ` ( has prd `long long* ok = (long long*)out;` ) )
    ( pb `reduce: EMPTY sentinel = 1<<63:    ` ( has prd `long long EMPTY = (long long)(1ULL << 63);` ) )
    ( pb `reduce: open-addressing CAS claim: ` ( has prd `atomicCAS(kp, (unsigned long long)EMPTY, (unsigned long long)kk)` ) )
    ( pb `reduce: folds into the value slot: ` ( has prd `swarm_atomic_op(&out[2*s + 1], vv)` ) )
    ( pb `reduce: count folds 1.0/element:   ` ( has prd `double vv = 1.0;` ) )
    ( pb `reduce: out sized 16 bytes/slot:   ` ( has prd `: i obytes * kbins 16` ) )
    ( pb `reduce: K in argv (needk):         ` ( has prd `: i kbins ( nurl_str_to_int ( nurl_argv_get 4 ) )` ) )
    ( pb `reduce: keys pre-init to EMPTY:    ` ( has prd `( nurl_poke zh * zk 2 << 1 63 )` ) )
    ( pb `reduce: vals pre-init to identity: ` ( has prd `( nurl_poke zh + * zk 2 1 0 )` ) )
    ( string_free prd )
    // sum uses '+', count identity 0; a max reduce uses fmax + the −∞ identity
    : String prmax ( cuda_wrap `__device__ long long key(long long x) { return x % 3; } __device__ double value(long long x) { return (double)x; }` 3 ( gpu_mode_shuffle_reduce ) 0 0 )
    ( pb `reduce max: fmax combine:          ` ( has prmax `fmax(__longlong_as_double(assumed), v)` ) )
    ( pb `reduce max: −∞ identity bits:      ` ( has prmax `( nurl_poke zh + * zk 2 1 -4503599627370496 )` ) )
    ( pb `reduce max: value() (not 1.0):     ` ( has prmax `double vv = value(x)` ) )
    ( string_free prmax )
    // reduce over a dataset: key/value take v = in[x - lo]
    : String prds ( cuda_wrap `__device__ long long key(long long x, double v) { return (long long)v % 7; } __device__ double value(long long x, double v) { return v; }` 0 ( gpu_mode_shuffle_reduce ) 0 1 )
    ( pb `reduce+data: kernel takes in ptr:  ` ( has prds `double* out, long long K, const double* in` ) )
    ( pb `reduce+data: key(x, (double)in[x - lo]):   ` ( has prds `key(x, (double)in[x - lo])` ) )
    ( string_free prds )
    : String ppar ( cuda_wrap `__device__ double f(long long x, const double* p) { return p[0]; }` 0 ( gpu_mode_scalar ) 1 0 )
    ( pb `params: kernel takes double* p:  ` ( has ppar `double* out, const double* p` ) )
    ( pb `params: f called as f(x, p):     ` ( has ppar `double v = f(x, p)` ) )
    ( pb `params: argv tail parsed:        ` ( has ppar `nurl_argv_get + pbase pk` ) )
    ( pb `params: uploaded with HtoD:      ` ( has ppar `cuMemcpyHtoD dp ph pbytes` ) )
    ( string_free ppar )

    // ── dataset splices (has_data) ────────────────────────────────
    : String pdat ( cuda_wrap `__device__ double f(long long x, double v) { return v; }` 0 ( gpu_mode_scalar ) 0 1 )
    ( pb `data: kernel takes double* in:   ` ( has pdat `double* out, const double* in` ) )
    ( pb `data: f called with in[x - lo]:  ` ( has pdat `f(x, (double)in[x - lo])` ) )
    ( pb `data: inpath read from argv 3:   ` ( has pdat `nurl_argv_get 3` ) )
    ( pb `data: slice read with fread:     ` ( has pdat `fread # s ih 1 ibytes ifh` ) )
    ( pb `data: slice uploaded HtoD:       ` ( has pdat `cuMemcpyHtoD din ih ibytes` ) )
    ( string_free pdat )
    : String pdp ( cuda_wrap `__device__ double f(long long x, double v, const double* p) { return v * p[0]; }` 0 ( gpu_mode_scalar ) 1 1 )
    ( pb `data+params call order:          ` ( has pdp `f(x, (double)in[x - lo], p)` ) )
    ( pb `data+params kernel sig order:    ` ( has pdp `const double* in, const double* p` ) )
    ( string_free pdp )
    : String pdh ( cuda_wrap `__device__ long long bin(long long x, double v) { return (long long)v; }` 0 ( gpu_mode_hist ) 0 1 )
    ( pb `hist+data bin(x, (double)in[x - lo]):    ` ( has pdh `bin(x, (double)in[x - lo])` ) )
    ( pb `hist+data default val matches:   ` ( has pdh `val(long long x, double v) { return 1.0; }` ) )
    ( string_free pdh )

    // ── typed datasets (has_data = dtype code): f32 / i32 / i64 ───────
    // The buffer is declared in its native width and each element cast to
    // double; the in-file byte count uses the element size.
    : String pf32 ( cuda_wrap `__device__ double f(long long x, double v) { return v; }` 0 ( gpu_mode_scalar ) 0 ( data_dtype_f32 ) )
    ( pb `f32: buffer is const float* in:   ` ( has pf32 `const float* in` ) )
    ( pb `f32: load cast to double:         ` ( has pf32 `f(x, (double)in[x - lo])` ) )
    ( pb `f32: in-file bytes use esz 4:     ` ( has pf32 `: i ibytes * - hi lo 4` ) )
    ( string_free pf32 )
    : String pi32 ( cuda_wrap `__device__ double f(long long x, double v) { return v; }` 0 ( gpu_mode_scalar ) 0 ( data_dtype_i32 ) )
    ( pb `i32: buffer is const int* in:     ` ( has pi32 `const int* in` ) )
    ( pb `i32: in-file bytes use esz 4:     ` ( has pi32 `: i ibytes * - hi lo 4` ) )
    ( string_free pi32 )
    : String pi64 ( cuda_wrap `__device__ double f(long long x, double v) { return v; }` 0 ( gpu_mode_scalar ) 0 ( data_dtype_i64 ) )
    ( pb `i64: buffer is const long long* in:` ( has pi64 `const long long* in` ) )
    ( pb `i64: in-file bytes use esz 8:     ` ( has pi64 `: i ibytes * - hi lo 8` ) )
    ( string_free pi64 )

    // ── GPU chunk payload v3 (dataset slice) round-trip ───────────
    : ( Vec u ) dslice ( vec_new [u] )
    : ~ i db 0
    ~ < db 16 { ( vec_push [u] dslice # u db ) = db + db 1 }  // 2 f64s = [102,103)
    : ( Vec i ) noprm ( vec_new [i] )
    : ( Vec u ) mb2 ( vec_new [u] )
    ( vec_push [u] mb2 9 )
    : ( Vec u ) pay3 ( wasm_gpu_chunk_payload ( gpu_mode_scalar ) 102 104 0 noprm dslice mb2 )
    : GpuChunk g3 ( wasm_gpu_chunk_decode pay3 )
    ( pb `payload v3 decodes ok:           ` ? == . g3 ok 1 T F )
    ( pb `payload v3 slice round-trips:    ` & == ( vec_len [u] . g3 data ) 16 == ?? ( vec_get [u] . g3 data 15 ) { T x → # i x F → 0 } 15 )
    ( pb `payload v3 module intact:        ` & == ( vec_len [u] . g3 wasm ) 1 == ?? ( vec_get [u] . g3 wasm 0 ) { T x → # i x F → 0 } 9 )
    ( gpu_chunk_free g3 ) ( vec_free [u] pay3 )
    // a slice whose length disagrees with [lo, hi) is rejected
    : ( Vec u ) pay3b ( wasm_gpu_chunk_payload ( gpu_mode_scalar ) 102 105 0 noprm dslice mb2 )
    : GpuChunk g3b ( wasm_gpu_chunk_decode pay3b )
    ( pb `payload v3 wrong dlen rejected:  ` ? == . g3b ok 1 F T )
    ( gpu_chunk_free g3b ) ( vec_free [u] pay3b )
    ( vec_free [u] dslice ) ( vec_free [i] noprm ) ( vec_free [u] mb2 )

    // ── GPU chunk payload v2 codec round-trip ─────────────────────
    : ( Vec i ) prm ( vec_new [i] )
    ( vec_push [i] prm 4611686018427387904 )  // 2.0
    ( vec_push [i] prm -4616189618054758400 )  // -1.0
    : ( Vec u ) modbytes ( vec_new [u] )
    ( vec_push [u] modbytes 1 ) ( vec_push [u] modbytes 2 ) ( vec_push [u] modbytes 3 )
    : ( Vec u ) nodata ( vec_new [u] )
    : ( Vec u ) pay ( wasm_gpu_chunk_payload ( gpu_mode_hist ) 100 200 16 prm nodata modbytes )
    : GpuChunk gc ( wasm_gpu_chunk_decode pay )
    ( pb `payload v2 decodes ok:           ` ? == . gc ok 1 T F )
    ( pb `payload v2 mode/lo/hi/K:         ` & & == . gc mode ( gpu_mode_hist ) & == . gc lo 100 == . gc hi 200 == . gc kbins 16 )
    ( pb `payload v2 params round-trip:    ` & == ( vec_len [i] . gc params ) 2 & == ?? ( vec_get [i] . gc params 0 ) { T x → x F → 0 } 4611686018427387904 == ?? ( vec_get [i] . gc params 1 ) { T x → x F → 0 } -4616189618054758400 )
    ( pb `payload v2 module bytes intact:  ` & == ( vec_len [u] . gc wasm ) 3 == ?? ( vec_get [u] . gc wasm 2 ) { T x → # i x F → 0 } 3 )
    ( pb `payload v2 (no data) empty data: ` ? == ( vec_len [u] . gc data ) 0 T F )
    ( gpu_chunk_free gc ) ( vec_free [u] pay ) ( vec_free [u] nodata ) ( vec_free [u] modbytes ) ( vec_free [i] prm )
    // truncated payload → ok=0
    : ( Vec u ) bad ( vec_new [u] )
    ( vec_push [u] bad 2 ) ( vec_push [u] bad 0 ) ( vec_push [u] bad 9 )
    : GpuChunk gb ( wasm_gpu_chunk_decode bad )
    ( pb `truncated payload rejected:      ` ? == . gb ok 1 F T )
    ( gpu_chunk_free gb ) ( vec_free [u] bad )

    // ── escaping: user text lands escaped inside the literal ──────
    // A user source with a backslash escape and a newline: the generated
    // program must carry them as the two-character sequences \\ and \n so the
    // generated literal decodes back to the original bytes.
    : String esc ( string_from `line1` )
    ( string_push_char esc 10 )  // real newline
    ( string_push_str esc `tab:` )
    ( string_push_char esc 9 )  // real tab
    ( string_push_str esc `bs:` )
    ( string_push_char esc 92 )  // real backslash
    ( string_push_str esc ` double f ` )
    : String pe ( cuda_wrap ( string_data esc ) 0 ( gpu_mode_scalar ) 0 0 )
    // expected two-char sequences in the generated TEXT
    : String want_nl ( string_new ) ( string_push_char want_nl 92 ) ( string_push_char want_nl 110 )
    : String want_tab ( string_new ) ( string_push_char want_tab 92 ) ( string_push_char want_tab 116 )
    : String want_bs ( string_new ) ( string_push_char want_bs 92 ) ( string_push_char want_bs 92 )
    ( pb `newline escaped in program text: ` ( has pe ( string_data want_nl ) ) )
    ( pb `tab escaped in program text:     ` ( has pe ( string_data want_tab ) ) )
    ( pb `backslash escaped in text:       ` ( has pe ( string_data want_bs ) ) )
    // and NO raw newline inside the generated string literal: every raw LF in
    // the program is a line break of generated CODE, never literal content —
    // the user's LF must not survive raw. Check the fragment `line1` is
    // followed by the ESCAPE, not by a raw LF.
    : i at ( nurl_str_find ( string_data pe ) `line1` )
    : b raw_lf ? >= at 0 == & # i . ( string_data pe ) + at 5 255 10 F
    ( pb `no raw LF inside the literal:    ` ? raw_lf F T )
    ( string_free want_nl ) ( string_free want_tab ) ( string_free want_bs )
    ( string_free pe ) ( string_free esc )

    // ── wasm handler result frame: [ok:1][partial:8] ──────────────
    // A forged (untagged) payload must yield a TAGGED ok=0 frame — the
    // coordinator counts it as a failed chunk, never folds it.
    : ( Vec u ) key ( token_key `caps-test` )
    : ( @ ( Vec u ) ( Vec u ) ) h ( wasm_handler key )
    : ( Vec u ) forged ( vec_new [u] )
    ( vec_push [u] forged 1 ) ( vec_push [u] forged 2 ) ( vec_push [u] forged 3 )
    : ( Vec u ) res ( h forged )
    : ~ b frame_ok F
    ?? ( token_untag key res ) {
        T body → {
            : i b0 ?? ( vec_get [u] body 0 ) { T x → # i x F → 9 }
            = frame_ok & == ( vec_len [u] body ) 9 == b0 0
            ( vec_free [u] body )
        }
        F → {}
    }
    ( pb `forged payload → tagged ok=0:    ` frame_ok )
    ( vec_free [u] res ) ( vec_free [u] forged ) ( vec_free [u] key )
    // release the handler closure's env (job_node_free does this in the node)
    : *u henv # *u h 1
    ? != # i henv 0 { ( nurl_free # s henv ) } {}

    // ── GPU handler: forged payload → tagged scalar ok=0 frame ────
    : ( Vec u ) gkey ( token_key `caps-test-gpu` )
    : ( @ ( Vec u ) ( Vec u ) ) gh ( wasm_gpu_handler gkey )
    : ( Vec u ) gforged ( vec_new [u] )
    ( vec_push [u] gforged 7 )
    : ( Vec u ) gres ( gh gforged )
    : ~ b gframe_ok F
    ?? ( token_untag gkey gres ) {
        T body → {
            : i b0 ?? ( vec_get [u] body 0 ) { T x → # i x F → 9 }
            = gframe_ok & == ( vec_len [u] body ) 9 == b0 0
            ( vec_free [u] body )
        }
        F → {}
    }
    ( pb `gpu forged payload → ok=0 frame: ` gframe_ok )
    ( vec_free [u] gres ) ( vec_free [u] gforged ) ( vec_free [u] gkey )
    : *u ghenv # *u gh 1
    ? != # i ghenv 0 { ( nurl_free # s ghenv ) } {}
    ^ 0
}
