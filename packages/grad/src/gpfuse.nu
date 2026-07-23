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
    GkBuf vtab  // i64 table: node id → val-buffer device address
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
    : GkBuf vb . pl vtab
    ? != . vb dptr 0 { ( gk_dbuf_free vb ) } {}
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
    = . pl vtab ( _gp_nobuf )
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
    ? up { = . pl ok T } {}
    ^ pl
}

// Fused forward: segments as one kernel each, everything else per-node.
@ gpfuse_forward * GProg pg * GpPlan pl → b {
    ? & . pg ok . pl ok {} { ^ F }
    ( gk_autosync F )
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
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}
