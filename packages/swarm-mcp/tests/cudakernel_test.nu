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
    : String p ( cuda_wrap `__device__ double f(long long x) { return (double)x; }` 0 )
    ( pb `program declares cuInit:         ` ( has p `@ cuInit i32 flags` ) )
    ( pb `program embeds swarm_map kernel: ` ( has p `swarm_map(long long lo, long long hi, double* out)` ) )
    ( pb `program has a main:              ` ( has p `@ main → i` ) )
    ( pb `sum combines with +:             ` ( has p `acc = acc + v` ) )
    ( pb `sum identity 0.0:                ` ( has p `double acc = 0.0` ) )
    ( pb `partial printed as f64 bits:     ` ( has p `f64_to_bits acc` ) )
    ( string_free p )

    // ── op splices ────────────────────────────────────────────────
    : String pmin ( cuda_wrap `__device__ double f(long long x) { return (double)x; }` 2 )
    ( pb `min combines with fmin:          ` ( has pmin `fmin(acc, v)` ) )
    ( pb `min identity +inf (CUDA):        ` ( has pmin `(1.0/0.0)` ) )
    ( pb `min identity +inf (host bits):   ` ( has pmin `bits_to_f64 9218868437227405312` ) )
    ( string_free pmin )
    : String pcnt ( cuda_wrap `__device__ double f(long long x) { return (double)x; }` 4 )
    ( pb `count maps truthiness to 1.0:    ` ( has pcnt `(f(x) != 0.0 ? 1.0 : 0.0)` ) )
    ( string_free pcnt )

    // ── escaping: user text lands escaped inside the literal ──────
    // A user source with a backslash escape and a newline: the generated
    // program must carry them as the two-character sequences \\ and \n so the
    // generated literal decodes back to the original bytes.
    : String esc ( string_from `line1` )
    ( string_push_char esc 10 )   // real newline
    ( string_push_str esc `tab:` )
    ( string_push_char esc 9 )    // real tab
    ( string_push_str esc `bs:` )
    ( string_push_char esc 92 )   // real backslash
    ( string_push_str esc ` double f ` )
    : String pe ( cuda_wrap ( string_data esc ) 0 )
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
    : ( @ ( Vec u ) ( Vec u ) ) h ( wasm_handler key 0 )
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
    ^ 0
}
