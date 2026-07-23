// grad/gpfuse.nu — MEGAKERNEL fusion: generate fused kernels from a
// captured program. The per-node replay's wall on small graphs is GPU-side
// per-kernel latency (~40 small dependent kernels per episode even under a
// CUDA graph); this module derives aegpu's fused shape FROM THE TAPE:
//
//   ROW-SPACE — a node is row-local when output row s depends only on row
//   s of its activation inputs plus whole leaf operands: elementwise
//   add/sub/mul/div ([B,c] with [B,c], [c] or [1]), every unary, and
//   matmul act[B,k] · W[k,c] with W a leaf. A maximal consecutive run of
//   row-local nodes becomes ONE generated kernel: block = row s, threads
//   stride each node's columns in node order, __syncthreads() between
//   nodes. Every node still writes ITS OWN buffer, so readbacks, unfused
//   consumers and gput_set_input work unchanged.
//
//   Everything else (reductions, transpose, bmm, slice/concat, the scalar
//   loss chain) keeps its per-node kernel — a graph that fuses nothing
//   simply runs exactly as before. Execution order is preserved because
//   segments are consecutive id ranges inside the normal walk.
//
// BIT-EXACTNESS: each fused element is computed by one thread with the
// same expression, intrinsics and inner-loop order as the per-node
// kernels, so fused output is bit-identical — the test gates on ==.
//
// The generated source is emitted in f64 with the __d*_rn discipline; an
// f32 program reuses the same substitution pass as the stock kernels
// (type, intrinsics, libm) — kernel names carry a per-plan id, so
// gpukit's name-keyed cache never collides across programs or dtypes.
//
// ABI: one pointer-table argument. The plan uploads every node's val-
// buffer address into an i64 table once; a kernel reads
//   const T* v<k> = (const T*)(unsigned long long)vt[<k>];
// which keeps every generated kernel's signature identical:
//   (const long long* vt, long long B)

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`
$ `grad.nu`
$ `gput.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

: GpPlan {
    b ok
    i kid  // unique plan id baked into kernel names
    i rows  // B — the fused chain's row count
    ( Vec i ) segs  // flattened (lo, hi) inclusive node-id ranges
    String src  // every generated kernel, one source (dtype-adjusted)
    ( Vec String ) knames  // kernel name per segment
    ( Vec String ) bnames  // bwd row-kernel per segment (empty = per-node)
    ( Vec String ) pnames  // bwd param-kernel per segment (empty = none)
    ( Vec i ) pgrid  // param-kernel grid blocks per segment
    GkBuf vtab  // i64 table: node id → val-buffer device address
    GkBuf gtab  // i64 table: node id → grad-buffer device address (0 = none)
    GkBuf ftab  // i64 pairs (grad ptr, n) — the one-launch zero fill
    i fcnt  // pair count in ftab
    String fillk  // fill kernel name
}

: ~ i g_gpm_next 1

// ── analysis ─────────────────────────────────────────────────────────

// Is node k row-local over B rows? (see the header for the definition)
@ _gpf_rowlocal * GProg pg i k i B → b {
    : GpNode nd ( _gp_node pg k )
    ? & == . nd rows B > . nd cols 0 {} { ^ F }
    : i op . nd op
    ? <= op ( gop_const ) { ^ F }
    ? & >= op ( gop_add ) <= op ( gop_div ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        // a must be the [B,c] activation side
        ? & == . na rows B == . na cols . nd cols {} { ^ F }
        // b: same shape, per-row vector [c], or scalar [1]
        ? & == . nb rows B == . nb cols . nd cols { ^ T } {}
        ? & == . nb rows 0 == . nb cols . nd cols { ^ T } {}
        ? == . nb n 1 { ^ T } {}
        ^ F
    } {}
    ? & >= op ( gop_neg ) <= op ( gop_sqrt ) {
        : GpNode na ( _gp_node pg . nd a )
        ^ & == . na rows B == . na cols . nd cols
    } {}
    ? == op ( gop_matmul ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        // activation [B,k] · leaf [k,c]
        ? & == . na rows B > . na cols 0 {} { ^ F }
        ? <= . nb op ( gop_const ) {} { ^ F }
        ^ & == . nb rows . na cols == . nb cols . nd cols
    } {}
    ^ F
}

// ── emission ─────────────────────────────────────────────────────────

@ _gpf_t String o i k → v {
    ( string_push_str o `v` )
    ( string_push_str o ( nurl_str_int k ) )
}

// (double)(<shortest round-trip literal>) — the f32 pass rewrites the cast,
// giving (float)(f64 literal) = the same value our uploads convert to.
@ _gpf_lit String o f v → v {
    ( string_push_str o `(double)(` )
    ( string_push_str o ( nurl_str_float v ) )
    ( string_push_str o `)` )
}

// Declare `const double* v<k>` (or mutable for outputs) from the table.
@ _gpf_decl String o i k b mut → v {
    ( string_push_str o ? mut `    double* ` `    const double* ` )
    ( _gpf_t o k )
    ( string_push_str o ` = (` )
    ( string_push_str o ? mut `double*` `const double*` )
    ( string_push_str o `)(unsigned long long)vt[` )
    ( string_push_str o ( nurl_str_int k ) )
    ( string_push_str o `];\n` )
}

// One fused-segment kernel over nodes [lo, hi].
@ _gpf_emit_seg * GProg pg i lo i hi i B s kname String o → v {
    ( string_push_str o `extern "C" __global__ void ` )
    ( string_push_str o kname )
    ( string_push_str o `(const long long* vt, long long B)\n{\n` )
    ( string_push_str o `    long long s = blockIdx.x;\n    if (s >= B) return;\n` )
    // buffer views: every referenced node id, outputs mutable
    : ( Vec i ) seen ( vec_new [i] )
    : ~ i k lo
    ~ <= k hi {
        : GpNode nd ( _gp_node pg k )
        ( _gpf_decl o k T )
        ( vec_push [i] seen k )
        : ~ i side 0
        ~ < side 2 {
            : i inid ? == side 0 . nd a . nd b
            ? >= inid 0 {
                : ~ b have F
                ? & >= inid lo <= inid hi { = have T } {}
                : ~ i q 0
                ~ < q ( vec_len [i] seen ) {
                    ? == ( _ti seen q ) inid { = have T } {}
                    = q + q 1
                }
                ? have {} {
                    ( _gpf_decl o inid F )
                    ( vec_push [i] seen inid )
                }
            } {}
            = side + side 1
        }
        = k + k 1
    }
    ( vec_free [i] seen )
    // node stages
    = k lo
    ~ <= k hi {
        : GpNode nd ( _gp_node pg k )
        : i op . nd op
        : i C . nd cols
        ( string_push_str o `    for (long long c = threadIdx.x; c < ` )
        ( string_push_str o ( nurl_str_int C ) )
        ( string_push_str o `; c += blockDim.x) {\n        ` )
        ? == op ( gop_matmul ) {
            // the gp_matmul inner loop verbatim: serial p, same intrinsics
            : GpNode na ( _gp_node pg . nd a )
            : i K . na cols
            ( string_push_str o `double acc = 0.0;\n        for (long long p = 0; p < ` )
            ( string_push_str o ( nurl_str_int K ) )
            ( string_push_str o `; p++) acc = __dadd_rn(acc, __dmul_rn(` )
            ( _gpf_t o . nd a )
            ( string_push_str o `[s * ` )
            ( string_push_str o ( nurl_str_int K ) )
            ( string_push_str o ` + p], ` )
            ( _gpf_t o . nd b )
            ( string_push_str o `[p * ` )
            ( string_push_str o ( nurl_str_int C ) )
            ( string_push_str o ` + c]));\n        ` )
            ( _gpf_t o k )
            ( string_push_str o `[s * ` )
            ( string_push_str o ( nurl_str_int C ) )
            ( string_push_str o ` + c] = acc` )
        } {
            ( _gpf_t o k )
            ( string_push_str o `[s * ` )
            ( string_push_str o ( nurl_str_int C ) )
            ( string_push_str o ` + c] = ` )
            ( _gpf_expr pg k o )
        }
        ( string_push_str o `;\n    }\n    __syncthreads();\n` )
        = k + k 1
    }
    ( string_push_str o `}\n` )
}

// `a`-side element of a binop/unary at (s, c).
@ _gpf_in String o * GProg pg i inid i C → v {
    ( _gpf_t o inid )
    ( string_push_str o `[s * ` )
    ( string_push_str o ( nurl_str_int C ) )
    ( string_push_str o ` + c]` )
}

// `b`-side element: matched shape, per-row vector, or scalar.
@ _gpf_inb String o * GProg pg i inid i C → v {
    : GpNode nb ( _gp_node pg inid )
    ? & == . nb rows 0 == . nb n 1 {
        ( _gpf_t o inid )
        ( string_push_str o `[0]` )
        ^ v
    } {}
    ? == . nb rows 0 {
        ( _gpf_t o inid )
        ( string_push_str o `[c]` )
        ^ v
    } {}
    ( _gpf_in o pg inid C )
}

// The per-element expression for fused node k — the EXACT per-node kernel
// arithmetic (gp_ew_bc / gp_scal / gp_trans / gp_matmul), spelled inline.
@ _gpf_expr * GProg pg i k String o → v {
    : GpNode nd ( _gp_node pg k )
    : i op . nd op
    : i C . nd cols
    ? == op ( gop_add ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_inb o pg . nd b C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_sub ) { ( string_push_str o `__dsub_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_inb o pg . nd b C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_mul ) { ( string_push_str o `__dmul_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_inb o pg . nd b C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_div ) { ( string_push_str o `__ddiv_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_inb o pg . nd b C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_neg ) { ( string_push_str o `__dsub_rn((double)(0), ` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_adds ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_lit o . nd s ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_muls ) { ( string_push_str o `__dmul_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_lit o . nd s ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_relu ) { ( _gpf_in o pg . nd a C ) ( string_push_str o ` > (double)(0) ? ` ) ( _gpf_in o pg . nd a C ) ( string_push_str o ` : (double)(0)` ) ^ v } {}
    ? == op ( gop_sigmoid ) { ( string_push_str o `__ddiv_rn(1.0, __dadd_rn(1.0, exp(__dsub_rn(0.0, ` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `))))` ) ^ v } {}
    ? == op ( gop_tanh ) {
        // two-step form via a statement expression is non-portable; inline:
        // e2 appears twice — identical exp() calls, same rounding.
        ( string_push_str o `__ddiv_rn(__dsub_rn(exp(__dmul_rn((double)(2), ` )
        ( _gpf_in o pg . nd a C )
        ( string_push_str o `)), (double)(1)), __dadd_rn(exp(__dmul_rn((double)(2), ` )
        ( _gpf_in o pg . nd a C )
        ( string_push_str o `)), (double)(1)))` )
        ^ v
    } {}
    ? == op ( gop_exp ) { ( string_push_str o `exp(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_log ) { ( string_push_str o `log(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_sqrt ) { ( string_push_str o `sqrt(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `)` ) ^ v } {}
    ( string_push_str o `0.0 /* unreachable */` )
}

// ── the plan ─────────────────────────────────────────────────────────

@ gpfuse_free * GpPlan pl → v {
    ( vec_free [i] . pl segs )
    ( string_free . pl src )
    : ~ i k 0
    ~ < k ( vec_len [String] . pl knames ) {
        ?? ( vec_get [String] . pl knames k ) { T x → { ( string_free x ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] . pl knames )
    = k 0
    ~ < k ( vec_len [String] . pl bnames ) {
        ?? ( vec_get [String] . pl bnames k ) { T x → { ( string_free x ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] . pl bnames )
    = k 0
    ~ < k ( vec_len [String] . pl pnames ) {
        ?? ( vec_get [String] . pl pnames k ) { T x → { ( string_free x ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] . pl pnames )
    ( vec_free [i] . pl pgrid )
    ( string_free . pl fillk )
    : GkBuf vb . pl vtab
    ? != . vb dptr 0 { ( gk_dbuf_free vb ) } {}
    : GkBuf gb . pl gtab
    ? != . gb dptr 0 { ( gk_dbuf_free gb ) } {}
    : GkBuf fb . pl ftab
    ? != . fb dptr 0 { ( gk_dbuf_free fb ) } {}
    ( nurl_free # s pl )
}

// Analyze the program, emit the fused-forward kernels, upload the pointer
// table. ok=F (with everything freed safe) when nothing fuses.
@ gpfuse_plan * GProg pg → *GpPlan {
    : *GpPlan pl # *GpPlan ( nurl_alloc Z GpPlan )
    = . pl ok F
    = . pl kid g_gpm_next
    = g_gpm_next + g_gpm_next 1
    = . pl segs ( vec_new [i] )
    = . pl src ( string_new )
    = . pl knames ( vec_new [String] )
    = . pl bnames ( vec_new [String] )
    = . pl pnames ( vec_new [String] )
    = . pl pgrid ( vec_new [i] )
    = . pl vtab ( _gp_nobuf )
    = . pl gtab ( _gp_nobuf )
    = . pl ftab ( _gp_nobuf )
    = . pl fcnt 0
    = . pl fillk ( string_new )
    ? . pg ok {} { ^ pl }
    // B = the most common 2-D row count among non-leaf nodes (the batch)
    : i nn ( vec_len [GpNode] . pg nodes )
    : ~ i B 0
    : ~ i bestc 0
    : ~ i k 0
    ~ < k nn {
        : GpNode nd ( _gp_node pg k )
        ? & > . nd op ( gop_const ) > . nd rows 0 {
            : ~ i cnt 0
            : ~ i j 0
            ~ < j nn {
                : GpNode m ( _gp_node pg j )
                ? & > . m op ( gop_const ) == . m rows . nd rows { = cnt + cnt 1 } {}
                = j + j 1
            }
            ? > cnt bestc { = bestc cnt = B . nd rows } {}
        } {}
        = k + k 1
    }
    ? > B 0 {} { ^ pl }
    = . pl rows B
    // maximal consecutive fusable runs (length >= 2)
    = k 0
    ~ < k nn {
        ? ( _gpf_rowlocal pg k B ) {
            : ~ i hi k
            ~ & < + hi 1 nn ( _gpf_rowlocal pg + hi 1 B ) { = hi + hi 1 }
            ? > hi k {
                ( vec_push [i] . pl segs k )
                ( vec_push [i] . pl segs hi )
            } {}
            = k + hi 1
        } { = k + k 1 }
    }
    ? > ( vec_len [i] . pl segs ) 0 {} { ^ pl }
    // emit every segment kernel
    : i nseg / ( vec_len [i] . pl segs ) 2
    = k 0
    ~ < k nseg {
        : String nm ( string_from `gpm` )
        ( string_push_str nm ( nurl_str_int . pl kid ) )
        ( string_push_str nm ? == . pg dtype 1 `f` `d` )
        ( string_push_str nm `_s` )
        ( string_push_str nm ( nurl_str_int k ) )
        ( _gpf_emit_seg pg ( _ti . pl segs * k 2 ) ( _ti . pl segs + * k 2 1 ) B ( string_data nm ) . pl src )
        ( vec_push [String] . pl knames nm )
        = k + k 1
    }
    // backward: row-space + param-space kernels per segment (order-safe
    // segments only), plus the one-launch gradient fill
    = k 0
    ~ < k nseg {
        : i lo ( _ti . pl segs * k 2 )
        : i hi ( _ti . pl segs + * k 2 1 )
        : String bn ( string_new )
        : String pn ( string_new )
        : ~ i pgr 0
        ? ( _gpf_bwd_ok pg lo hi B ) {
            : String cand ( string_from `gpm` )
            ( string_push_str cand ( nurl_str_int . pl kid ) )
            ( string_push_str cand ? == . pg dtype 1 `f` `d` )
            ( string_push_str cand `_b` )
            ( string_push_str cand ( nurl_str_int k ) )
            ? ( _gpf_emit_bwd_seg pg lo hi B ( string_data cand ) . pl src ) {
                ( string_push_str bn ( string_data cand ) )
                : String pc ( string_from `gpm` )
                ( string_push_str pc ( nurl_str_int . pl kid ) )
                ( string_push_str pc ? == . pg dtype 1 `f` `d` )
                ( string_push_str pc `_p` )
                ( string_push_str pc ( nurl_str_int k ) )
                : i mx ( _gpf_emit_param_seg pg lo hi B ( string_data pc ) . pl src )
                ? > mx 0 {
                    ( string_push_str pn ( string_data pc ) )
                    = pgr ( gk_grid mx 256 )
                } {}
                ( string_free pc )
            } {}
            ( string_free cand )
        } {}
        ( vec_push [String] . pl bnames bn )
        ( vec_push [String] . pl pnames pn )
        ( vec_push [i] . pl pgrid pgr )
        = k + k 1
    }
    ( string_push_str . pl fillk `gpm` )
    ( string_push_str . pl fillk ( nurl_str_int . pl kid ) )
    ( string_push_str . pl fillk ? == . pg dtype 1 `f` `d` )
    ( string_push_str . pl fillk `_fill` )
    ( _gpf_emit_fill ( string_data . pl fillk ) . pl src )

    // dtype adjustment: the same substitution pass the stock kernels use
    ? == . pg dtype 1 {
        : ~ s x ( string_data . pl src )
        = x ( _str_replace_all x `__dadd_rn` `__fadd_rn` )
        = x ( _str_replace_all x `__dsub_rn` `__fsub_rn` )
        = x ( _str_replace_all x `__dmul_rn` `__fmul_rn` )
        = x ( _str_replace_all x `__ddiv_rn` `__fdiv_rn` )
        = x ( _str_replace_all x `exp(` `expf(` )
        = x ( _str_replace_all x `log(` `logf(` )
        = x ( _str_replace_all x `sqrt(` `sqrtf(` )
        = x ( _str_replace_all x `double` `float` )
        : String nx ( string_from x )
        ( string_free . pl src )
        = . pl src nx
    } {}
    // pointer table: node id → val dptr
    : ( Vec i ) tv ( vec_new [i] )
    = k 0
    ~ < k nn {
        : GpNode nd ( _gp_node pg k )
        : GkBuf vb . nd val
        ( vec_push [i] tv . vb dptr )
        = k + k 1
    }
    = . pl vtab ( gk_dbuf_new . pg kit ( vec_len [i] tv ) GK_I64 )
    : ~ b up ( gk_buf_ok . pl vtab )
    = up & up ( gk_dbuf_upload_i . pg kit . pl vtab tv )
    ( vec_free [i] tv )
    // grad-pointer table + the (ptr, n) fill pairs
    : ( Vec i ) tg ( vec_new [i] )
    : ( Vec i ) tf2 ( vec_new [i] )
    = k 0
    ~ < k nn {
        : GpNode nd ( _gp_node pg k )
        : GkBuf gb2 . nd grad
        ? ( gk_buf_ok gb2 ) {
            ( vec_push [i] tg . gb2 dptr )
            ( vec_push [i] tf2 . gb2 dptr )
            ( vec_push [i] tf2 . gb2 n )
        } { ( vec_push [i] tg 0 ) }
        = k + k 1
    }
    = . pl gtab ( gk_dbuf_new . pg kit ( vec_len [i] tg ) GK_I64 )
    = up & up ( gk_buf_ok . pl gtab )
    = up & up ( gk_dbuf_upload_i . pg kit . pl gtab tg )
    ? > ( vec_len [i] tf2 ) 0 {
        = . pl ftab ( gk_dbuf_new . pg kit ( vec_len [i] tf2 ) GK_I64 )
        = up & up ( gk_buf_ok . pl ftab )
        = up & up ( gk_dbuf_upload_i . pg kit . pl ftab tf2 )
        = . pl fcnt / ( vec_len [i] tf2 ) 2
    } {}
    ( vec_free [i] tg )
    ( vec_free [i] tf2 )
    ? up { = . pl ok T } {}
    ^ pl
}

// Launches only (no sync policy) — shared by the direct path and the
// CUDA-graph capture.
@ _gpfuse_fwd_launches * GProg pg * GpPlan pl → b {
    : i nn ( vec_len [GpNode] . pg nodes )
    : i nseg / ( vec_len [i] . pl segs ) 2
    : ~ b r T
    : ~ i k 0
    : ~ i si 0
    ~ & < k nn r {
        ? & < si nseg == k ( _ti . pl segs * si 2 ) {
            : s nm ?? ( vec_get [String] . pl knames si ) { T x → ( string_data x ) F → `` }
            : ( Vec i ) a ( vec_new [i] )
            ( vec_push [i] a ( gk_arg_dev . pl vtab ) )
            ( vec_push [i] a ( gpu_arg_i64 . pl rows ) )
            = r ( gk_run_dev . pg kit ( string_data . pl src ) nm . pl rows 256 a )
            ( vec_free [i] a )
            = k + ( _ti . pl segs + * si 2 1 ) 1
            = si + si 1
        } {
            = r ( _gp_fwd_node pg k )
            = k + k 1
        }
    }
    ^ r
}

// Fused forward: segments as one kernel each, everything else per-node.
@ gpfuse_forward * GProg pg * GpPlan pl → b {
    ? & . pg ok . pl ok {} { ^ F }
    ( gk_autosync F )
    : b r ( _gpfuse_fwd_launches pg pl )
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}

// ── backward emission ────────────────────────────────────────────────
// Row-space gradient stages (dActivations) fuse into one kernel per
// segment, sweeping nodes hi→lo with __syncthreads between stages — the
// same launch order as the per-node reverse walk. Param-space targets
// (matmul leaf weights, broadcast ew operands) accumulate SERIALLY over
// rows per element — gp_bw_mm_b / gp_bw_accred verbatim — in a second
// kernel launched after the row kernel. A gradient element only ever
// belongs to one class, so the split preserves bit order; the one corner
// where a target could collect BOTH kinds inside a segment is detected
// by _gpf_bwd_ok and that segment honestly falls back to per-node.

@ _gpf_g String o i k → v {
    ( string_push_str o `g` )
    ( string_push_str o ( nurl_str_int k ) )
}

// double* g<k> = (double*)(unsigned long long)gt[<k>];
@ _gpf_gdecl String o i k → v {
    ( string_push_str o `    double* ` )
    ( _gpf_g o k )
    ( string_push_str o ` = (double*)(unsigned long long)gt[` )
    ( string_push_str o ( nurl_str_int k ) )
    ( string_push_str o `];\n` )
}

@ _gpf_seen ( Vec i ) seen i id → b {
    : ~ i q 0
    ~ < q ( vec_len [i] seen ) {
        ? == ( _ti seen q ) id { ^ T } {}
        = q + q 1
    }
    ( vec_push [i] seen id )
    ^ F
}

// g<id>[s * C + c]
@ _gpf_gel String o i id i C → v {
    ( _gpf_g o id )
    ( string_push_str o `[s * ` )
    ( string_push_str o ( nurl_str_int C ) )
    ( string_push_str o ` + c]` )
}

// Is ew input `inid` the same [B,c] shape as consumer `nd`?
@ _gpf_same * GProg pg i inid i B i C → b {
    : GpNode m ( _gp_node pg inid )
    ^ & == . m rows B == . m cols C
}

// accred wrapper: TARGET = __dadd_rn(TARGET, __dmul_rn(<sgn>, <src...>
@ _gpf_acc_open String o * GProg pg i tid i C s sgn → v {
    ( string_push_str o `        ` )
    ( _gpf_gel o tid C )
    ( string_push_str o ` = __dadd_rn(` )
    ( _gpf_gel o tid C )
    ( string_push_str o `, __dmul_rn(` )
    ( string_push_str o sgn )
    ( string_push_str o `, ` )
}

// One row-space backward stage loop `for c < W` around `body` pushes.
@ _gpf_stage_open String o i W → v {
    ( string_push_str o `    for (long long c = threadIdx.x; c < ` )
    ( string_push_str o ( nurl_str_int W ) )
    ( string_push_str o `; c += blockDim.x) {\n` )
}

@ _gpf_stage_close String o → v {
    ( string_push_str o `    }\n    __syncthreads();\n` )
}

// Row-space bwd kernel body for segment [lo,hi]; stage count returned.
@ _gpf_emit_bwd_stages * GProg pg i lo i hi i B String o ( Vec i ) vids ( Vec i ) gids → i {
    : ~ i stages 0
    : ~ i k hi
    ~ >= k lo {
        : GpNode nd ( _gp_node pg k )
        : i op . nd op
        : i C . nd cols
        ? == . nd reach 1 {
            ? & >= op ( gop_add ) <= op ( gop_div ) {
                : GpNode na ( _gp_node pg . nd a )
                : GpNode nb ( _gp_node pg . nd b )
                : b needa == . na reach 1
                : ~ b needb F
                ? & ( _gpf_same pg . nd b B C ) == . nb reach 1 { = needb T } {}
                ? | needa needb {
                    = stages + stages 1
                    : b _s ( _gpf_seen gids k )
                    ( _gpf_stage_open o C )
                    ? needa {
                        : b _t ( _gpf_seen gids . nd a )
                        ( _gpf_acc_open o pg . nd a C `1.0` )
                        ? == op ( gop_add ) { ( _gpf_gel o k C ) } {}
                        ? == op ( gop_sub ) { ( _gpf_gel o k C ) } {}
                        ? == op ( gop_mul ) {
                            : b _v ( _gpf_seen vids . nd b )
                            ( string_push_str o `__dmul_rn(` )
                            ( _gpf_gel o k C )
                            ( string_push_str o `, ` )
                            ( _gpf_inb o pg . nd b C )
                            ( string_push_str o `)` )
                        } {}
                        ? == op ( gop_div ) {
                            : b _v ( _gpf_seen vids . nd b )
                            ( string_push_str o `__ddiv_rn(` )
                            ( _gpf_gel o k C )
                            ( string_push_str o `, ` )
                            ( _gpf_inb o pg . nd b C )
                            ( string_push_str o `)` )
                        } {}
                        ( string_push_str o `));\n` )
                    } {}
                    ? needb {
                        : b _t ( _gpf_seen gids . nd b )
                        : s sg2 ? == op ( gop_sub ) `-1.0` ? == op ( gop_div ) `-1.0` `1.0`
                        ( _gpf_acc_open o pg . nd b C sg2 )
                        ? == op ( gop_add ) { ( _gpf_gel o k C ) } {}
                        ? == op ( gop_sub ) { ( _gpf_gel o k C ) } {}
                        ? == op ( gop_mul ) {
                            : b _v ( _gpf_seen vids . nd a )
                            ( string_push_str o `__dmul_rn(` )
                            ( _gpf_gel o k C )
                            ( string_push_str o `, ` )
                            ( _gpf_in o pg . nd a C )
                            ( string_push_str o `)` )
                        } {}
                        ? == op ( gop_div ) {
                            // scr = (g ⊙ out) / b — gp_bw's exact chain
                            : b _v ( _gpf_seen vids k )
                            : b _v2 ( _gpf_seen vids . nd b )
                            ( string_push_str o `__ddiv_rn(__dmul_rn(` )
                            ( _gpf_gel o k C )
                            ( string_push_str o `, ` )
                            ( _gpf_in o pg k C )
                            ( string_push_str o `), ` )
                            ( _gpf_inb o pg . nd b C )
                            ( string_push_str o `)` )
                        } {}
                        ( string_push_str o `));\n` )
                    } {}
                    ( _gpf_stage_close o )
                } {}
            } {}
            ? & >= op ( gop_neg ) <= op ( gop_sqrt ) {
                : GpNode na ( _gp_node pg . nd a )
                ? == . na reach 1 {
                    = stages + stages 1
                    : b _s ( _gpf_seen gids k )
                    : b _t ( _gpf_seen gids . nd a )
                    ( _gpf_stage_open o C )
                    ( string_push_str o `        double gi = ` )
                    ( _gpf_gel o k C )
                    ( string_push_str o `;\n        ` )
                    ( _gpf_gel o . nd a C )
                    ( string_push_str o ` = ` )
                    // gp_bw_unary's exact per-op accumulate expression
                    ? == op ( gop_neg ) {
                        ( string_push_str o `__dsub_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, gi)` )
                    } {}
                    ? == op ( gop_adds ) {
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, gi)` )
                    } {}
                    ? == op ( gop_muls ) {
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __dmul_rn(gi, ` )
                        ( _gpf_lit o . nd s )
                        ( string_push_str o `))` )
                    } {}
                    ? == op ( gop_relu ) {
                        : b _v ( _gpf_seen vids k )
                        ( _gpf_in o pg k C )
                        ( string_push_str o ` > 0.0 ? __dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, gi) : ` )
                        ( _gpf_gel o . nd a C )
                    } {}
                    ? == op ( gop_sigmoid ) {
                        : b _v ( _gpf_seen vids k )
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __dmul_rn(gi, __dmul_rn(` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `, __dsub_rn(1.0, ` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `))))` )
                    } {}
                    ? == op ( gop_tanh ) {
                        : b _v ( _gpf_seen vids k )
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __dmul_rn(gi, __dsub_rn(1.0, __dmul_rn(` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `, ` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `))))` )
                    } {}
                    ? == op ( gop_exp ) {
                        : b _v ( _gpf_seen vids k )
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __dmul_rn(gi, ` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `))` )
                    } {}
                    ? == op ( gop_log ) {
                        : b _v ( _gpf_seen vids . nd a )
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __ddiv_rn(gi, ` )
                        ( _gpf_in o pg . nd a C )
                        ( string_push_str o `))` )
                    } {}
                    ? == op ( gop_sqrt ) {
                        : b _v ( _gpf_seen vids k )
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __ddiv_rn(gi, __dmul_rn(2.0, ` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `)))` )
                    } {}
                    ( string_push_str o `;\n` )
                    ( _gpf_stage_close o )
                } {}
            } {}
            ? == op ( gop_matmul ) {
                : GpNode na ( _gp_node pg . nd a )
                ? == . na reach 1 {
                    = stages + stages 1
                    : b _s ( _gpf_seen gids k )
                    : b _t ( _gpf_seen gids . nd a )
                    : b _v ( _gpf_seen vids . nd b )
                    : i K . na cols
                    : i N2 . nd cols
                    // gp_bw_mm_a verbatim: dA[s,p] += Σ_j g[s,j]·W[p,j]
                    ( _gpf_stage_open o K )
                    ( string_push_str o `        double acc = 0.0;\n        for (long long j = 0; j < ` )
                    ( string_push_str o ( nurl_str_int N2 ) )
                    ( string_push_str o `; j++) acc = __dadd_rn(acc, __dmul_rn(` )
                    ( _gpf_g o k )
                    ( string_push_str o `[s * ` )
                    ( string_push_str o ( nurl_str_int N2 ) )
                    ( string_push_str o ` + j], ` )
                    ( _gpf_t o . nd b )
                    ( string_push_str o `[c * ` )
                    ( string_push_str o ( nurl_str_int N2 ) )
                    ( string_push_str o ` + j]));\n        ` )
                    ( _gpf_gel o . nd a K )
                    ( string_push_str o ` = __dadd_rn(` )
                    ( _gpf_gel o . nd a K )
                    ( string_push_str o `, acc);\n` )
                    ( _gpf_stage_close o )
                } {}
            } {}
        } {}
        = k - k 1
    }
    ^ stages
}

// Param-space jobs of segment [lo,hi], descending consumer order, encoded
// as (target, kind, consumer) triples — kind 0 = matmul dW, 1 = ew b-side.
@ _gpf_param_jobs * GProg pg i lo i hi i B ( Vec i ) jobs → v {
    : ~ i k hi
    ~ >= k lo {
        : GpNode nd ( _gp_node pg k )
        : i op . nd op
        ? == . nd reach 1 {
            ? & >= op ( gop_add ) <= op ( gop_div ) {
                : GpNode nb ( _gp_node pg . nd b )
                ? & == . nb reach 1 == ( _gpf_same pg . nd b B . nd cols ) F {
                    ( vec_push [i] jobs . nd b )
                    ( vec_push [i] jobs 1 )
                    ( vec_push [i] jobs k )
                } {}
            } {}
            ? == op ( gop_matmul ) {
                : GpNode nb ( _gp_node pg . nd b )
                ? == . nb reach 1 {
                    ( vec_push [i] jobs . nd b )
                    ( vec_push [i] jobs 0 )
                    ( vec_push [i] jobs k )
                } {}
            } {}
        } {}
        = k - k 1
    }
}

// Order safety: no gradient may collect BOTH row-space and param-space
// contributions inside one segment (the split would reorder them).
@ _gpf_bwd_ok * GProg pg i lo i hi i B → b {
    : ( Vec i ) rowt ( vec_new [i] )
    : ~ i k lo
    ~ <= k hi {
        : GpNode nd ( _gp_node pg k )
        : i op . nd op
        ? == . nd reach 1 {
            ? > op ( gop_const ) {
                : GpNode na ( _gp_node pg . nd a )
                ? == . na reach 1 { : b _x ( _gpf_seen rowt . nd a ) } {}
                ? & >= op ( gop_add ) <= op ( gop_div ) {
                    : GpNode nb ( _gp_node pg . nd b )
                    ? & ( _gpf_same pg . nd b B . nd cols ) == . nb reach 1 {
                        : b _y ( _gpf_seen rowt . nd b )
                    } {}
                } {}
            } {}
        } {}
        = k + k 1
    }
    : ( Vec i ) jobs ( vec_new [i] )
    ( _gpf_param_jobs pg lo hi B jobs )
    : ~ b ok T
    : ~ i q 0
    ~ < q ( vec_len [i] jobs ) {
        : i tid ( _ti jobs q )
        : ~ i w 0
        ~ < w ( vec_len [i] rowt ) {
            ? == ( _ti rowt w ) tid { = ok F } {}
            = w + w 1
        }
        = q + q 3
    }
    ( vec_free [i] rowt )
    ( vec_free [i] jobs )
    ^ ok
}

// The param-space kernel: one grid-stride stage per distinct target, jobs
// serial inside each thread — gp_bw_mm_b / gp_bw_accred element order.
// Returns the widest target n (grid sizing); 0 when there are no jobs.
@ _gpf_emit_param * GProg pg i lo i hi i B String body ( Vec i ) vids ( Vec i ) gids → i {
    : ( Vec i ) jobs ( vec_new [i] )
    ( _gpf_param_jobs pg lo hi B jobs )
    : i nj / ( vec_len [i] jobs ) 3
    ? > nj 0 {} { ( vec_free [i] jobs ) ^ 0 }
    : ~ i maxn 0
    : ( Vec i ) done ( vec_new [i] )
    : ~ i q 0
    ~ < q nj {
        : i tid ( _ti jobs * q 3 )
        ? ( _gpf_seen done tid ) { = q + q 1 } {
            : GpNode nt ( _gp_node pg tid )
            : b _g ( _gpf_seen gids tid )
            ? > . nt n maxn { = maxn . nt n } {}
            ( string_push_str body `    for (long long t = (long long)blockIdx.x * blockDim.x + threadIdx.x; t < ` )
            ( string_push_str body ( nurl_str_int . nt n ) )
            ( string_push_str body `; t += (long long)gridDim.x * blockDim.x) {\n` )
            // every job hitting this target, in collected (descending) order
            : ~ i w 0
            ~ < w nj {
                ? == ( _ti jobs * w 3 ) tid {
                    : i kind ( _ti jobs + * w 3 1 )
                    : i kc ( _ti jobs + * w 3 2 )
                    : GpNode nd ( _gp_node pg kc )
                    : i C . nd cols
                    : b _gk ( _gpf_seen gids kc )
                    ? == kind 0 {
                        // gp_bw_mm_b: dW[p,j] += Σ_i A[i,p]·g[i,j], serial i
                        : GpNode na ( _gp_node pg . nd a )
                        : i K . na cols
                        : b _va ( _gpf_seen vids . nd a )
                        ( string_push_str body `        { long long p = t / ` )
                        ( string_push_str body ( nurl_str_int C ) )
                        ( string_push_str body `, j = t % ` )
                        ( string_push_str body ( nurl_str_int C ) )
                        ( string_push_str body `;\n          double acc = 0.0;\n          for (long long i = 0; i < ` )
                        ( string_push_str body ( nurl_str_int B ) )
                        ( string_push_str body `; i++) acc = __dadd_rn(acc, __dmul_rn(` )
                        ( _gpf_t body . nd a )
                        ( string_push_str body `[i * ` )
                        ( string_push_str body ( nurl_str_int K ) )
                        ( string_push_str body ` + p], ` )
                        ( _gpf_g body kc )
                        ( string_push_str body `[i * ` )
                        ( string_push_str body ( nurl_str_int C ) )
                        ( string_push_str body ` + j]));\n          ` )
                        ( _gpf_g body tid )
                        ( string_push_str body `[t] = __dadd_rn(` )
                        ( _gpf_g body tid )
                        ( string_push_str body `[t], acc); }\n` )
                    } {
                        // gp_bw_accred: serial odometer over the B rows (or
                        // all B·C elements for a scalar target)
                        : i op . nd op
                        : b scal == . nt n 1
                        : i tf ? scal * B C B
                        : s sgn ? | == op ( gop_sub ) == op ( gop_div ) `-1.0` `1.0`
                        ( string_push_str body `        { double g0 = ` )
                        ( _gpf_g body tid )
                        ( string_push_str body `[t];\n          for (long long q = 0; q < ` )
                        ( string_push_str body ( nurl_str_int tf ) )
                        ( string_push_str body `; q++) g0 = __dadd_rn(g0, __dmul_rn(` )
                        ( string_push_str body sgn )
                        ( string_push_str body `, ` )
                        // the source element at flat q (scalar) / (q, t) (vector)
                        : String ix ( string_new )
                        ? scal {
                            ( string_push_str ix `[q]` )
                        } {
                            ( string_push_str ix `[q * ` )
                            ( string_push_str ix ( nurl_str_int C ) )
                            ( string_push_str ix ` + t]` )
                        }
                        ? == op ( gop_mul ) {
                            : b _va ( _gpf_seen vids . nd a )
                            ( string_push_str body `__dmul_rn(` )
                            ( _gpf_g body kc )
                            ( string_push_str body ( string_data ix ) )
                            ( string_push_str body `, ` )
                            ( _gpf_t body . nd a )
                            ( string_push_str body ( string_data ix ) )
                            ( string_push_str body `)` )
                        } {
                            ? == op ( gop_div ) {
                                : b _vk ( _gpf_seen vids kc )
                                : b _vt ( _gpf_seen vids tid )
                                ( string_push_str body `__ddiv_rn(__dmul_rn(` )
                                ( _gpf_g body kc )
                                ( string_push_str body ( string_data ix ) )
                                ( string_push_str body `, ` )
                                ( _gpf_t body kc )
                                ( string_push_str body ( string_data ix ) )
                                ( string_push_str body `), ` )
                                ( _gpf_t body tid )
                                ( string_push_str body ? scal `[0]` `[t]` )
                                ( string_push_str body `)` )
                            } {
                                ( _gpf_g body kc )
                                ( string_push_str body ( string_data ix ) )
                            }
                        }
                        ( string_free ix )
                        ( string_push_str body `));\n          ` )
                        ( _gpf_g body tid )
                        ( string_push_str body `[t] = g0; }\n` )
                    }
                } {}
                = w + w 1
            }
            ( string_push_str body `    }\n` )
            = q + q 1
        }
    }
    ( vec_free [i] done )
    ( vec_free [i] jobs )
    ^ maxn
}

// Assemble the row-space bwd kernel; F when the segment has no stages.
@ _gpf_emit_bwd_seg * GProg pg i lo i hi i B s kname String o → b {
    : String body ( string_new )
    : ( Vec i ) vids ( vec_new [i] )
    : ( Vec i ) gids ( vec_new [i] )
    : i stages ( _gpf_emit_bwd_stages pg lo hi B body vids gids )
    ? > stages 0 {} {
        ( string_free body )
        ( vec_free [i] vids )
        ( vec_free [i] gids )
        ^ F
    }
    ( string_push_str o `extern "C" __global__ void ` )
    ( string_push_str o kname )
    ( string_push_str o `(const long long* vt, const long long* gt, long long B)\n{\n` )
    ( string_push_str o `    long long s = blockIdx.x;\n    if (s >= B) return;\n` )
    : ~ i q 0
    ~ < q ( vec_len [i] vids ) {
        ( _gpf_decl o ( _ti vids q ) F )
        = q + q 1
    }
    = q 0
    ~ < q ( vec_len [i] gids ) {
        ( _gpf_gdecl o ( _ti gids q ) )
        = q + q 1
    }
    ( string_push_str o ( string_data body ) )
    ( string_push_str o `}\n` )
    ( string_free body )
    ( vec_free [i] vids )
    ( vec_free [i] gids )
    ^ T
}

// Assemble the param-space kernel; returns the widest target n (0 = none).
@ _gpf_emit_param_seg * GProg pg i lo i hi i B s kname String o → i {
    : String body ( string_new )
    : ( Vec i ) vids ( vec_new [i] )
    : ( Vec i ) gids ( vec_new [i] )
    : i maxn ( _gpf_emit_param pg lo hi B body vids gids )
    ? > maxn 0 {} {
        ( string_free body )
        ( vec_free [i] vids )
        ( vec_free [i] gids )
        ^ 0
    }
    ( string_push_str o `extern "C" __global__ void ` )
    ( string_push_str o kname )
    ( string_push_str o `(const long long* vt, const long long* gt)\n{\n` )
    : ~ i q 0
    ~ < q ( vec_len [i] vids ) {
        ( _gpf_decl o ( _ti vids q ) F )
        = q + q 1
    }
    = q 0
    ~ < q ( vec_len [i] gids ) {
        ( _gpf_gdecl o ( _ti gids q ) )
        = q + q 1
    }
    ( string_push_str o ( string_data body ) )
    ( string_push_str o `}\n` )
    ( string_free body )
    ( vec_free [i] vids )
    ( vec_free [i] gids )
    ^ maxn
}

// The one-launch gradient zero fill over an (ptr, n) pair table.
@ _gpf_emit_fill s kname String o → v {
    ( string_push_str o `extern "C" __global__ void ` )
    ( string_push_str o kname )
    ( string_push_str o `(const long long* ft, long long nb)\n{\n` )
    ( string_push_str o `    long long j = blockIdx.x;\n    if (j >= nb) return;\n` )
    ( string_push_str o `    double* p = (double*)(unsigned long long)ft[2 * j];\n` )
    ( string_push_str o `    long long n = ft[2 * j + 1];\n` )
    ( string_push_str o `    for (long long t = threadIdx.x; t < n; t += blockDim.x) p[t] = 0.0;\n` )
    ( string_push_str o `}\n` )
}

// Fused backward: one zero-fill launch, the seed, then the reverse walk
// with row-space + param-space kernels standing in for fused segments.
@ _gpfuse_bwd_launches * GProg pg * GpPlan pl → b {
    : ~ b r T
    ? > . pl fcnt 0 {
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . pl ftab ) )
        ( vec_push [i] a ( gpu_arg_i64 . pl fcnt ) )
        = r ( gk_run_dev . pg kit ( string_data . pl src ) ( string_data . pl fillk ) . pl fcnt 256 a )
        ( vec_free [i] a )
    } {
        : i n2 ( vec_len [GpNode] . pg nodes )
        : ~ i q 0
        ~ & < q n2 r {
            : GpNode nd ( _gp_node pg q )
            : GkBuf gb2 . nd grad
            ? ( gk_buf_ok gb2 ) { = r ( _gp_fill_buf pg gb2 0.0 ) } {}
            = q + q 1
        }
    }
    ? r {
        : GpNode lo2 ( _gp_node pg . pg loss )
        : GkBuf lg . lo2 grad
        ? ( gk_buf_ok lg ) { = r ( _gp_fill_buf pg lg 1.0 ) } {}
    } {}
    : i nseg / ( vec_len [i] . pl segs ) 2
    : ~ i k . pg loss
    ~ & >= k 0 r {
        : ~ i si -1
        : ~ i w 0
        ~ < w nseg {
            ? == ( _ti . pl segs + * w 2 1 ) k {
                : s bn ?? ( vec_get [String] . pl bnames w ) { T x → ( string_data x ) F → `` }
                ? > ( nurl_str_len bn ) 0 { = si w } {}
            } {}
            = w + w 1
        }
        ? >= si 0 {
            : s bn2 ?? ( vec_get [String] . pl bnames si ) { T x → ( string_data x ) F → `` }
            : ( Vec i ) a ( vec_new [i] )
            ( vec_push [i] a ( gk_arg_dev . pl vtab ) )
            ( vec_push [i] a ( gk_arg_dev . pl gtab ) )
            ( vec_push [i] a ( gpu_arg_i64 . pl rows ) )
            = r ( gk_run_dev . pg kit ( string_data . pl src ) bn2 . pl rows 256 a )
            ( vec_free [i] a )
            : s pn ?? ( vec_get [String] . pl pnames si ) { T x → ( string_data x ) F → `` }
            ? & r > ( nurl_str_len pn ) 0 {
                : ( Vec i ) a2 ( vec_new [i] )
                ( vec_push [i] a2 ( gk_arg_dev . pl vtab ) )
                ( vec_push [i] a2 ( gk_arg_dev . pl gtab ) )
                = r ( gk_run_dev . pg kit ( string_data . pl src ) pn ( _ti . pl pgrid si ) 256 a2 )
                ( vec_free [i] a2 )
            } {}
            = k - ( _ti . pl segs * si 2 ) 1
        } {
            = r ( _gp_bwd_node pg k )
            = k - k 1
        }
    }
    ^ r
}

@ gpfuse_backward * GProg pg * GpPlan pl → b {
    ? & . pg ok . pl ok {} { ^ F }
    ( gk_autosync F )
    : b r ( _gpfuse_bwd_launches pg pl )
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}

// The megakernel episode as ONE CUDA graph: fused forward + fused
// backward + the optimizer, captured once. Per episode the host does
// gput_set_input + gpopt_prepare + gput_episode — the identical driver
// loop as the per-node graph, just with ~5 kernels inside instead of ~40.
@ gpfuse_graph_capture_train * GProg pg * GpPlan pl * GpOpt go → b {
    ? & & . pg ok . pl ok . go ok {} { ^ F }
    ? == . pg gexec 0 {} { ^ T }
    ? ( _gpopt_ensure go pg ) {} { ^ F }
    : *GpuKit kit . pg kit
    ? ( gpu_graph_begin . kit gpu ) {} { ^ F }
    ( gk_autosync F )
    : ~ b r ( _gpfuse_fwd_launches pg pl )
    = r & r ( _gpfuse_bwd_launches pg pl )
    = r & r ( _gpopt_launches go pg )
    ( gk_autosync T )
    : i exec ( gpu_graph_end . kit gpu )
    ? & r != exec 0 {
        = . pg gexec exec
        ^ T
    } {}
    ? != exec 0 { ( gpu_graph_free exec ) } {}
    ^ F
}
